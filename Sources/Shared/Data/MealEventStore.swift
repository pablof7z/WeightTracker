import Foundation
import SwiftData

public extension Notification.Name {
    static let mealEventDidChange = Notification.Name("mealEventDidChange")
}

/// Repository for `MealEvent` rows. Events are upserted by the
/// `(dayStart(ateAt), slotId)` pair when a slot id is supplied, so that
/// re-logging the same meal on the same day replaces the prior entry rather
/// than creating duplicates. Free-form events (no slot id) always insert.
@MainActor
public final class MealEventStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Read

    /// All events whose day-stamp equals the given day.
    public func events(on day: Date) -> [MealEvent] {
        let target = Reading.dayStart(of: day)
        let predicate = #Predicate<MealEvent> { $0.date == target }
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.minutesFromMidnight, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// All events whose day-stamp falls in `[from, to]`, inclusive.
    public func events(from: Date, to: Date) -> [MealEvent] {
        let lo = Reading.dayStart(of: from)
        let hi = Reading.dayStart(of: to)
        let predicate = #Predicate<MealEvent> { $0.date >= lo && $0.date <= hi }
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.minutesFromMidnight, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// All events in the trailing `days` window (inclusive of today).
    public func eventsInLastDays(_ days: Int, now: Date = Date()) -> [MealEvent] {
        let today = Reading.dayStart(of: now)
        let lo = Calendar.current.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        return events(from: lo, to: today)
    }

    /// Look up the (day, slot) event used for upsert. Returns nil if no
    /// matching row exists. Slot id is required because nil-slot rows are
    /// always treated as standalone inserts.
    public func event(on day: Date, slotId: UUID) -> MealEvent? {
        let target = Reading.dayStart(of: day)
        let predicate = #Predicate<MealEvent> {
            $0.date == target && $0.slotId == slotId
        }
        let descriptor = FetchDescriptor<MealEvent>(predicate: predicate)
        return try? context.fetch(descriptor).first
    }

    // MARK: - Write

    /// Insert or update a meal event. When `slotId` is provided we upsert by
    /// `(dayStart(ateAt), slotId)`; when it's nil we always insert a new row.
    @discardableResult
    public func upsert(
        slotId: UUID?,
        slotNameSnapshot: String?,
        scheduleId: UUID?,
        ateAt: Date,
        status: MealEventStatus,
        hungerBefore: HungerLevel? = nil,
        hungerAfter: HungerLevel? = nil,
        note: String? = nil,
        now: Date = Date()
    ) -> MealEvent {
        let calendar = Calendar.current

        if let slotId, let existing = event(on: ateAt, slotId: slotId) {
            existing.ateAt = ateAt
            let comps = calendar.dateComponents([.hour, .minute], from: ateAt)
            existing.minutesFromMidnight = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            existing.loggedAt = now
            existing.scheduleId = scheduleId
            if let slotNameSnapshot {
                existing.slotNameSnapshot = slotNameSnapshot
            }
            existing.status = status
            existing.hungerBefore = hungerBefore
            existing.hungerAfter = hungerAfter
            existing.note = note
            save()
            NotificationCenter.default.post(name: .mealEventDidChange, object: nil)
            return existing
        }

        let row = MealEvent(
            ateAt: ateAt,
            loggedAt: now,
            scheduleId: scheduleId,
            slotId: slotId,
            slotNameSnapshot: slotNameSnapshot,
            status: status,
            hungerBefore: hungerBefore,
            hungerAfter: hungerAfter,
            note: note,
            calendar: calendar
        )
        context.insert(row)
        save()
        NotificationCenter.default.post(name: .mealEventDidChange, object: nil)
        return row
    }

    public func delete(_ event: MealEvent) {
        context.delete(event)
        save()
        NotificationCenter.default.post(name: .mealEventDidChange, object: nil)
    }

    private func save() {
        do { try context.save() } catch { print("[MealEventStore] save failed: \(error)") }
    }
}
