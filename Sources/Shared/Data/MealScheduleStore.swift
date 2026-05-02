import Foundation
import SwiftData

public extension Notification.Name {
    static let mealScheduleDidChange = Notification.Name("mealScheduleDidChange")
}

/// Input describing a single meal slot for `MealScheduleStore.replaceCurrentPeriod`
/// / `insertInitialPeriod`. Mirrors `MealSlot`'s init parameters but without an id
/// or schedule id so callers don't have to thread those through.
public struct MealSlotInput: Sendable {
    public let name: String
    public let minutesFromMidnight: Int
    public let kind: MealKind
    public let sortOrder: Int?
    public let kcalPercent: Double?
    public let proteinPercent: Double?
    public let fatPercent: Double?
    public let carbsPercent: Double?
    public let note: String?
    public let calculatedKcal: Int?
    public let calculatedProteinG: Int?
    public let calculatedFatG: Int?
    public let calculatedCarbsG: Int?
    public let calculatedAt: Date?
    public let foodDescription: String?

    public init(
        name: String,
        minutesFromMidnight: Int,
        kind: MealKind = .custom,
        sortOrder: Int? = nil,
        kcalPercent: Double? = nil,
        proteinPercent: Double? = nil,
        fatPercent: Double? = nil,
        carbsPercent: Double? = nil,
        note: String? = nil,
        calculatedKcal: Int? = nil,
        calculatedProteinG: Int? = nil,
        calculatedFatG: Int? = nil,
        calculatedCarbsG: Int? = nil,
        calculatedAt: Date? = nil,
        foodDescription: String? = nil
    ) {
        self.name = name
        self.minutesFromMidnight = minutesFromMidnight
        self.kind = kind
        self.sortOrder = sortOrder
        self.kcalPercent = kcalPercent
        self.proteinPercent = proteinPercent
        self.fatPercent = fatPercent
        self.carbsPercent = carbsPercent
        self.note = note
        self.calculatedKcal = calculatedKcal
        self.calculatedProteinG = calculatedProteinG
        self.calculatedFatG = calculatedFatG
        self.calculatedCarbsG = calculatedCarbsG
        self.calculatedAt = calculatedAt
        self.foodDescription = foodDescription
    }
}

/// Append-only repository for `MealSchedulePeriod` rows and their child
/// `MealSlot` rows. Periods are versioned by `cutStartDate`. The "current"
/// period for a given cut is the one with no `endDate`; previous periods are
/// stamped with `endDate = yesterday` whenever a new period takes effect.
@MainActor
public final class MealScheduleStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Read

    /// All periods for a cut, oldest first.
    public func periods(forCutStartDate cutStartDate: Date) -> [MealSchedulePeriod] {
        let key = Reading.dayStart(of: cutStartDate)
        let predicate = #Predicate<MealSchedulePeriod> { $0.cutStartDate == key }
        let descriptor = FetchDescriptor<MealSchedulePeriod>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The currently active period (no `endDate`) for a cut, if any.
    public func currentPeriod(forCutStartDate cutStartDate: Date) -> MealSchedulePeriod? {
        periods(forCutStartDate: cutStartDate).first(where: { $0.endDate == nil })
    }

    /// Slots belonging to a schedule, sorted by `sortOrder` ascending.
    public func slots(forScheduleId scheduleId: UUID) -> [MealSlot] {
        let predicate = #Predicate<MealSlot> { $0.scheduleId == scheduleId }
        let descriptor = FetchDescriptor<MealSlot>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Look up a single slot by id. Returns nil when the slot has been deleted
    /// or isn't part of any schedule the current store can see.
    public func slot(byId id: UUID) -> MealSlot? {
        let predicate = #Predicate<MealSlot> { $0.id == id }
        let descriptor = FetchDescriptor<MealSlot>(predicate: predicate)
        return try? context.fetch(descriptor).first
    }

    // MARK: - Write

    /// Replace the currently active period with a new one (or mutate-in-place
    /// if the active one began today).
    @discardableResult
    public func replaceCurrentPeriod(
        cutStartDate: Date,
        slotInputs: [MealSlotInput],
        note: String? = nil,
        now: Date = Date()
    ) throws -> MealSchedulePeriod {
        let today = Reading.dayStart(of: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today

        if let active = currentPeriod(forCutStartDate: cutStartDate) {
            if active.startDate == today {
                // Mutate in place: swap slots and refresh note.
                deleteSlots(forScheduleId: active.id)
                active.note = note
                insertSlots(scheduleId: active.id, inputs: slotInputs)
                save()
                NotificationCenter.default.post(name: .mealScheduleDidChange, object: nil)
                return active
            } else {
                active.endDate = yesterday
            }
        }

        let new = MealSchedulePeriod(
            cutStartDate: cutStartDate,
            startDate: today,
            note: note
        )
        context.insert(new)
        insertSlots(scheduleId: new.id, inputs: slotInputs)
        save()
        NotificationCenter.default.post(name: .mealScheduleDidChange, object: nil)
        return new
    }

    /// Insert the very first meal schedule period for a cut. Use this when the
    /// user first sets up meals so the period's `startDate` matches the cut's
    /// start date.
    @discardableResult
    public func insertInitialPeriod(
        cutStartDate: Date,
        startDate: Date,
        slotInputs: [MealSlotInput],
        note: String? = nil
    ) throws -> MealSchedulePeriod {
        let period = MealSchedulePeriod(
            cutStartDate: cutStartDate,
            startDate: startDate,
            note: note
        )
        context.insert(period)
        insertSlots(scheduleId: period.id, inputs: slotInputs)
        save()
        NotificationCenter.default.post(name: .mealScheduleDidChange, object: nil)
        return period
    }

    /// Update the calculated macros on a single slot without rewriting the
    /// whole schedule. Used after `calculate_meal` to attach the result to the
    /// slot the coach was reasoning about.
    public func updateSlotMacros(
        slotId: UUID,
        kcal: Int,
        proteinG: Int,
        fatG: Int,
        carbsG: Int,
        foodDescription: String?,
        now: Date = Date()
    ) throws {
        guard let slot = slot(byId: slotId) else {
            throw MealScheduleStoreError.slotNotFound(slotId)
        }
        slot.calculatedKcal = kcal
        slot.calculatedProteinG = proteinG
        slot.calculatedFatG = fatG
        slot.calculatedCarbsG = carbsG
        slot.calculatedAt = now
        if let foodDescription, !foodDescription.isEmpty {
            slot.foodDescription = foodDescription
        }
        save()
        NotificationCenter.default.post(name: .mealScheduleDidChange, object: nil)
    }

    public func delete(_ period: MealSchedulePeriod) {
        deleteSlots(forScheduleId: period.id)
        context.delete(period)
        save()
        NotificationCenter.default.post(name: .mealScheduleDidChange, object: nil)
    }

    public func deleteAll(forCutStartDate cutStartDate: Date) {
        for p in periods(forCutStartDate: cutStartDate) {
            deleteSlots(forScheduleId: p.id)
            context.delete(p)
        }
        save()
        NotificationCenter.default.post(name: .mealScheduleDidChange, object: nil)
    }

    // MARK: - Helpers

    private func insertSlots(scheduleId: UUID, inputs: [MealSlotInput]) {
        for (idx, input) in inputs.enumerated() {
            let slot = MealSlot(
                scheduleId: scheduleId,
                name: input.name,
                minutesFromMidnight: input.minutesFromMidnight,
                kind: input.kind,
                sortOrder: input.sortOrder ?? (idx * 1000 + input.minutesFromMidnight),
                kcalPercent: input.kcalPercent,
                proteinPercent: input.proteinPercent,
                fatPercent: input.fatPercent,
                carbsPercent: input.carbsPercent,
                note: input.note,
                calculatedKcal: input.calculatedKcal,
                calculatedProteinG: input.calculatedProteinG,
                calculatedFatG: input.calculatedFatG,
                calculatedCarbsG: input.calculatedCarbsG,
                calculatedAt: input.calculatedAt,
                foodDescription: input.foodDescription
            )
            context.insert(slot)
        }
    }

    private func deleteSlots(forScheduleId scheduleId: UUID) {
        for slot in slots(forScheduleId: scheduleId) {
            context.delete(slot)
        }
    }

    private func save() {
        do { try context.save() } catch { print("[MealScheduleStore] save failed: \(error)") }
    }
}

public enum MealScheduleStoreError: Error, Equatable, Sendable {
    case slotNotFound(UUID)
}
