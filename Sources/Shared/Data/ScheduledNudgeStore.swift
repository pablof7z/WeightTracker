import Foundation
import SwiftData
import UserNotifications

/// Append-only repository for `ScheduledNudge` records. Nudges represent
/// coach-authored reminders or behavioural prompts that should fire at a
/// specific time (or in response to some other trigger). The store also
/// reconciles its pending records with `UNUserNotificationCenter` so that
/// time-based nudges actually surface to the user.
@MainActor
public final class ScheduledNudgeStore {
    /// `UserDefaults` key used to persist the user's daily step target.
    /// Centralised here so the coach, activity card and any other client
    /// agree on the location.
    public static let stepTargetKey = "coach.dailyStepTarget"

    /// Default daily step target used when the user has not configured one.
    public static let defaultStepTarget = 8_000

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Read

    /// All nudges that have not been delivered and have not been cancelled,
    /// ordered by `createdAt` ascending (oldest first).
    public func pendingNudges() -> [ScheduledNudge] {
        let predicate = #Predicate<ScheduledNudge> { nudge in
            nudge.delivered == false && nudge.cancelledAt == nil
        }
        let descriptor = FetchDescriptor<ScheduledNudge>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Look up a nudge by id. Returns `nil` if the record has been deleted
    /// or doesn't exist.
    public func nudge(byId id: UUID) -> ScheduledNudge? {
        let predicate = #Predicate<ScheduledNudge> { $0.id == id }
        let descriptor = FetchDescriptor<ScheduledNudge>(predicate: predicate)
        return try? context.fetch(descriptor).first
    }

    // MARK: - Write

    /// Insert a brand new pending nudge.
    @discardableResult
    public func schedule(
        message: String,
        triggerType: NudgeTriggerType,
        triggerParams: String,
        expiresAt: Date?
    ) -> ScheduledNudge {
        let nudge = ScheduledNudge(
            triggerType: triggerType,
            triggerParams: triggerParams,
            message: message,
            scheduledAt: scheduledAtFromTriggerParams(triggerType: triggerType, params: triggerParams),
            expiresAt: expiresAt,
            delivered: false,
            cancelledAt: nil
        )
        context.insert(nudge)
        save()
        return nudge
    }

    /// Mark a nudge as cancelled. Cancelled nudges are not returned from
    /// `pendingNudges()` and are removed from the notification centre on the
    /// next call to `syncToNotificationCenter()`.
    public func cancel(id: UUID) {
        guard let nudge = nudge(byId: id) else { return }
        nudge.cancelledAt = Date()
        save()
    }

    /// Mark a nudge as delivered. Delivered nudges drop out of `pendingNudges()`
    /// but remain in the store as historical records.
    public func markDelivered(_ nudge: ScheduledNudge) {
        nudge.delivered = true
        save()
    }

    // MARK: - Notification Center sync

    /// Reconcile the persisted nudges with `UNUserNotificationCenter`.
    ///
    /// 1. Schedules a `UNCalendarNotificationTrigger` for any pending,
    ///    future-dated nudge that isn't already in the centre.
    /// 2. Removes any pending requests for nudges that have been cancelled
    ///    locally (so the user doesn't receive a buzz for a recalled
    ///    suggestion).
    public func syncToNotificationCenter() async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let existingIDs = Set(existing.map { $0.identifier })

        let now = Date()
        let pending = pendingNudges()

        for nudge in pending {
            guard let scheduledAt = nudge.scheduledAt, scheduledAt > now else { continue }
            let identifier = nudge.id.uuidString
            if existingIDs.contains(identifier) { continue }

            let content = UNMutableNotificationContent()
            content.body = nudge.message
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: scheduledAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                print("[ScheduledNudgeStore] failed to add notification: \(error)")
            }
        }

        // Remove pending centre requests for nudges that were cancelled
        // locally. We look for cancelled records whose identifier is still
        // present in the notification centre.
        let cancelledPredicate = #Predicate<ScheduledNudge> { $0.cancelledAt != nil }
        let cancelledDescriptor = FetchDescriptor<ScheduledNudge>(predicate: cancelledPredicate)
        let cancelled = (try? context.fetch(cancelledDescriptor)) ?? []
        let toRemove = cancelled
            .map { $0.id.uuidString }
            .filter { existingIDs.contains($0) }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toRemove)
        }
    }

    // MARK: - Helpers

    /// Convenience for callers that pass a literal `Date` rather than encoding
    /// it into `triggerParams`. Returns the parsed `Date` if `triggerParams`
    /// looks like a JSON object with a `"fireAt"` ISO-8601 string. Returns
    /// `nil` otherwise — callers can still set `scheduledAt` themselves on
    /// the returned record before saving.
    private func scheduledAtFromTriggerParams(
        triggerType: NudgeTriggerType,
        params: String
    ) -> Date? {
        guard triggerType == .timeOfDay else { return nil }
        guard let data = params.data(using: .utf8) else { return nil }
        struct Params: Decodable { let fireAt: String? }
        let formatter = ISO8601DateFormatter()
        if let parsed = try? JSONDecoder().decode(Params.self, from: data),
           let raw = parsed.fireAt,
           let date = formatter.date(from: raw) {
            return date
        }
        return nil
    }

    private func save() {
        do { try context.save() } catch { print("[ScheduledNudgeStore] save failed: \(error)") }
    }
}
