import Foundation
import SwiftData

public enum MacroDeviationError: Error, Equatable {
    case futureDate
    case beyondBackfillWindow
    case insideUntrackedRange
    case frozenOutsideEditWindow
    case noActivePlan
}

/// Repository for `MacroDeviation` rows. Enforces the backfill / edit windows
/// described in the macro spec:
/// * `backfillLimitDays = 30` — log/edit only within the last 30 days.
/// * `editWindowDays = 7`    — edits to existing rows allowed for 7 days; older
///   rows are frozen except for delete (which is allowed within 30d).
@MainActor
public final class MacroDeviationStore {
    public static let backfillLimitDays = 30
    public static let editWindowDays = 7

    private let container: ModelContainer
    private let untrackedStore: MacroUntrackedRangeStore
    private let planStore: MacroPlanStore
    private var context: ModelContext { container.mainContext }

    public init(
        container: ModelContainer,
        untrackedStore: MacroUntrackedRangeStore,
        planStore: MacroPlanStore
    ) {
        self.container = container
        self.untrackedStore = untrackedStore
        self.planStore = planStore
    }

    // MARK: - Read

    public func deviations(forCutStartDate cutStartDate: Date) -> [MacroDeviation] {
        let key = Reading.dayStart(of: cutStartDate)
        let predicate = #Predicate<MacroDeviation> { $0.cutStartDate == key }
        let descriptor = FetchDescriptor<MacroDeviation>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func deviationsInLastDays(_ days: Int, cutStartDate: Date, now: Date = Date()) -> [MacroDeviation] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Reading.dayStart(of: now))
            ?? Reading.dayStart(of: now)
        return deviations(forCutStartDate: cutStartDate).filter { $0.date >= cutoff }
    }

    public func deviation(on day: Date, cutStartDate: Date) -> MacroDeviation? {
        let target = Reading.dayStart(of: day)
        let key = Reading.dayStart(of: cutStartDate)
        let predicate = #Predicate<MacroDeviation> {
            $0.cutStartDate == key && $0.date == target
        }
        let descriptor = FetchDescriptor<MacroDeviation>(predicate: predicate)
        return try? context.fetch(descriptor).first
    }

    // MARK: - Write

    /// Insert or update a deviation for a given day. Same-day re-log replaces
    /// the existing row in place. Throws when the date violates the backfill
    /// or edit-window rules, or falls inside an untracked range.
    @discardableResult
    public func upsert(
        date: Date,
        cutStartDate: Date,
        direction: MacroDirection,
        magnitude: MacroMagnitude,
        note: String? = nil,
        now: Date = Date()
    ) throws -> MacroDeviation {
        let today = Reading.dayStart(of: now)
        let target = Reading.dayStart(of: date)
        let cutKey = Reading.dayStart(of: cutStartDate)

        guard target <= today else { throw MacroDeviationError.futureDate }

        let daysAgo = Calendar.current.dateComponents([.day], from: target, to: today).day ?? 0
        guard daysAgo <= Self.backfillLimitDays else {
            throw MacroDeviationError.beyondBackfillWindow
        }

        if untrackedStore.range(covering: target, cutStartDate: cutKey) != nil {
            throw MacroDeviationError.insideUntrackedRange
        }

        guard let plan = planStore.period(coveringDay: target, cutStartDate: cutKey)
            ?? planStore.currentPeriod(forCutStartDate: cutKey)
        else {
            throw MacroDeviationError.noActivePlan
        }

        if let existing = deviation(on: target, cutStartDate: cutKey) {
            // Same-day re-log: always allowed (target == today).
            // Older rows: only editable inside the edit window.
            if daysAgo > Self.editWindowDays {
                throw MacroDeviationError.frozenOutsideEditWindow
            }
            existing.direction = direction
            existing.magnitude = magnitude
            existing.note = note
            existing.planPeriodId = plan.id
            existing.loggedAt = now
            save()
            return existing
        }

        let row = MacroDeviation(
            date: target,
            cutStartDate: cutKey,
            planPeriodId: plan.id,
            direction: direction,
            magnitude: magnitude,
            note: note,
            loggedAt: now
        )
        context.insert(row)
        save()
        return row
    }

    /// Delete is allowed within the 30-day backfill window regardless of
    /// the edit window.
    public func delete(_ deviation: MacroDeviation, now: Date = Date()) throws {
        let today = Reading.dayStart(of: now)
        let daysAgo = Calendar.current.dateComponents([.day], from: deviation.date, to: today).day ?? 0
        guard daysAgo <= Self.backfillLimitDays else {
            throw MacroDeviationError.beyondBackfillWindow
        }
        context.delete(deviation)
        save()
    }

    public func deleteAll(forCutStartDate cutStartDate: Date) {
        for d in deviations(forCutStartDate: cutStartDate) {
            context.delete(d)
        }
        save()
    }

    private func save() {
        do { try context.save() } catch { print("[MacroDeviationStore] save failed: \(error)") }
    }
}
