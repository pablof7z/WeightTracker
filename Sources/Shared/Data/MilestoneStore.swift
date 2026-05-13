import Foundation
import SwiftData

public extension Notification.Name {
    static let milestoneDidChange = Notification.Name("milestoneDidChange")
}

public enum MilestoneStoreError: Error, Equatable {
    case emptyName
}

/// Repository for `Milestone` rows. Milestones are simple day-stamped named
/// events. All reads return rows sorted by `date` ascending. The store
/// posts `.milestoneDidChange` after any mutation so UI can refresh.
@MainActor
public final class MilestoneStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Read

    /// All milestones, oldest first.
    public func all() -> [Milestone] {
        let descriptor = FetchDescriptor<Milestone>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Milestones whose date is on or after `from`, oldest first.
    public func upcoming(from date: Date, calendar: Calendar = .current) -> [Milestone] {
        let cutoff = calendar.startOfDay(for: date)
        let predicate = #Predicate<Milestone> { $0.date >= cutoff }
        let descriptor = FetchDescriptor<Milestone>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Write

    /// Insert a new milestone. Name is trimmed; throws `.emptyName` when
    /// blank. Date is normalized to start-of-day by the model initializer.
    @discardableResult
    public func add(name: String, date: Date, now: Date = Date()) throws -> Milestone {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MilestoneStoreError.emptyName }

        let row = Milestone(name: trimmed, date: date, createdAt: now)
        context.insert(row)
        save()
        NotificationCenter.default.post(name: .milestoneDidChange, object: nil)
        return row
    }

    /// Delete a milestone by its UUID. Returns true when a row was found
    /// and deleted.
    @discardableResult
    public func delete(id: UUID) -> Bool {
        let predicate = #Predicate<Milestone> { $0.id == id }
        let descriptor = FetchDescriptor<Milestone>(predicate: predicate)
        guard let row = try? context.fetch(descriptor).first else { return false }
        context.delete(row)
        save()
        NotificationCenter.default.post(name: .milestoneDidChange, object: nil)
        return true
    }

    /// Delete every milestone whose `name` contains `query` (case-insensitive
    /// substring). Returns the number of rows deleted. Useful for agent UX
    /// where the user says "remove my trip milestone".
    @discardableResult
    public func delete(byNameMatching query: String) -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let needle = trimmed.lowercased()
        let rows = all().filter { $0.name.lowercased().contains(needle) }
        guard !rows.isEmpty else { return 0 }
        for row in rows {
            context.delete(row)
        }
        save()
        NotificationCenter.default.post(name: .milestoneDidChange, object: nil)
        return rows.count
    }

    private func save() {
        do { try context.save() } catch { print("[MilestoneStore] save failed: \(error)") }
    }
}
