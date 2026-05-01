import Foundation
import SwiftData

public enum MacroUntrackedRangeError: Error, Equatable {
    case invalidRange
    case futureEnd
}

/// Repository for `MacroUntrackedRange` rows. Each range marks a contiguous
/// span where the user explicitly opted out of tracking — used to suppress
/// implicit "fine" days in the chart and history views.
@MainActor
public final class MacroUntrackedRangeStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func ranges(forCutStartDate cutStartDate: Date) -> [MacroUntrackedRange] {
        let key = Reading.dayStart(of: cutStartDate)
        let predicate = #Predicate<MacroUntrackedRange> { $0.cutStartDate == key }
        let descriptor = FetchDescriptor<MacroUntrackedRange>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func range(covering day: Date, cutStartDate: Date) -> MacroUntrackedRange? {
        let key = Reading.dayStart(of: day)
        return ranges(forCutStartDate: cutStartDate).first(where: { $0.contains(key) })
    }

    @discardableResult
    public func insert(
        cutStartDate: Date,
        startDate: Date,
        endDate: Date,
        reason: UntrackedReason,
        customReasonLabel: String? = nil,
        now: Date = Date()
    ) throws -> MacroUntrackedRange {
        let today = Reading.dayStart(of: now)
        let s = Reading.dayStart(of: startDate)
        let e = Reading.dayStart(of: endDate)
        guard s <= e else { throw MacroUntrackedRangeError.invalidRange }
        guard e <= today else { throw MacroUntrackedRangeError.futureEnd }

        let row = MacroUntrackedRange(
            cutStartDate: cutStartDate,
            startDate: s,
            endDate: e,
            reason: reason,
            customReasonLabel: customReasonLabel
        )
        context.insert(row)
        save()
        return row
    }

    public func delete(_ range: MacroUntrackedRange) {
        context.delete(range)
        save()
    }

    public func deleteAll(forCutStartDate cutStartDate: Date) {
        for r in ranges(forCutStartDate: cutStartDate) {
            context.delete(r)
        }
        save()
    }

    private func save() {
        do { try context.save() } catch { print("[MacroUntrackedRangeStore] save failed: \(error)") }
    }
}
