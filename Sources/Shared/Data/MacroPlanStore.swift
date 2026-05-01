import Foundation
import SwiftData

/// Append-only repository for `MacroPlanPeriod` rows. Periods are versioned by
/// `cutStartDate`. The "current" period for a given cut is the one with no
/// `endDate`; previous periods are stamped with `endDate = yesterday` whenever
/// a new period takes effect.
@MainActor
public final class MacroPlanStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Read

    /// All periods for a cut, oldest first.
    public func periods(forCutStartDate cutStartDate: Date) -> [MacroPlanPeriod] {
        let key = Reading.dayStart(of: cutStartDate)
        let predicate = #Predicate<MacroPlanPeriod> { $0.cutStartDate == key }
        let descriptor = FetchDescriptor<MacroPlanPeriod>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The currently active period (no `endDate`) for a cut, if any.
    public func currentPeriod(forCutStartDate cutStartDate: Date) -> MacroPlanPeriod? {
        periods(forCutStartDate: cutStartDate).first(where: { $0.endDate == nil })
    }

    /// The period that covers a given day, if any.
    public func period(coveringDay day: Date, cutStartDate: Date) -> MacroPlanPeriod? {
        let target = Reading.dayStart(of: day)
        for p in periods(forCutStartDate: cutStartDate) {
            let start = p.startDate
            let end = p.endDate ?? .distantFuture
            if target >= start && target <= end {
                return p
            }
        }
        return nil
    }

    // MARK: - Write

    /// Replace the currently active period with a new one.
    ///
    /// - If the active period began *today*, mutate it in place to avoid
    ///   stamping a zero-day historical period.
    /// - Otherwise stamp the active period with `endDate = yesterday` and
    ///   insert a new period with `startDate = today`.
    @discardableResult
    public func replaceCurrentPeriod(
        cutStartDate: Date,
        kcal: Int,
        proteinG: Int?,
        fatG: Int?,
        carbsG: Int?,
        tag: MacroPlanTag = .standard,
        customTagLabel: String? = nil,
        note: String? = nil,
        now: Date = Date()
    ) -> MacroPlanPeriod {
        let today = Reading.dayStart(of: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today

        if let active = currentPeriod(forCutStartDate: cutStartDate) {
            if active.startDate == today {
                active.kcal = kcal
                active.proteinG = proteinG
                active.fatG = fatG
                active.carbsG = carbsG
                active.tag = tag
                active.customTagLabel = customTagLabel
                active.note = note
                save()
                return active
            } else {
                active.endDate = yesterday
            }
        }

        let new = MacroPlanPeriod(
            cutStartDate: cutStartDate,
            startDate: today,
            kcal: kcal,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            tag: tag,
            customTagLabel: customTagLabel,
            note: note
        )
        context.insert(new)
        save()
        return new
    }

    /// Insert the very first plan period for a brand-new cut. Use this from
    /// `StartCutSheet` so the period's `startDate` matches the cut's start.
    @discardableResult
    public func insertInitialPeriod(
        cutStartDate: Date,
        startDate: Date,
        kcal: Int,
        proteinG: Int?,
        fatG: Int?,
        carbsG: Int?,
        tag: MacroPlanTag = .standard,
        customTagLabel: String? = nil,
        note: String? = nil
    ) -> MacroPlanPeriod {
        let period = MacroPlanPeriod(
            cutStartDate: cutStartDate,
            startDate: startDate,
            kcal: kcal,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            tag: tag,
            customTagLabel: customTagLabel,
            note: note
        )
        context.insert(period)
        save()
        return period
    }

    public func delete(_ period: MacroPlanPeriod) {
        context.delete(period)
        save()
    }

    public func deleteAll(forCutStartDate cutStartDate: Date) {
        for p in periods(forCutStartDate: cutStartDate) {
            context.delete(p)
        }
        save()
    }

    private func save() {
        do { try context.save() } catch { print("[MacroPlanStore] save failed: \(error)") }
    }
}
