import Foundation
import SwiftData

@MainActor
public protocol ReadingRepository: AnyObject {
    func allReadings() -> [Reading]
    func readings(in range: ClosedRange<Date>) -> [Reading]
    func reading(on date: Date) -> Reading?
    func mostRecent() -> Reading?
    @discardableResult
    func insert(_ reading: Reading) -> Reading
    func update(_ reading: Reading)
    func delete(_ reading: Reading)
    func deleteAll()
    func deleteRange(_ range: ClosedRange<Date>)
    func bulkInsert(_ readings: [Reading], replacingExisting: Bool)
}

@MainActor
public final class SwiftDataReadingRepository: ReadingRepository {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func allReadings() -> [Reading] {
        let descriptor = FetchDescriptor<Reading>(sortBy: [SortDescriptor(\.date, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func readings(in range: ClosedRange<Date>) -> [Reading] {
        let lo = range.lowerBound
        let hi = range.upperBound
        let predicate = #Predicate<Reading> { $0.date >= lo && $0.date <= hi }
        let descriptor = FetchDescriptor<Reading>(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func reading(on date: Date) -> Reading? {
        let day = Reading.dayStart(of: date)
        let predicate = #Predicate<Reading> { $0.date == day }
        let descriptor = FetchDescriptor<Reading>(predicate: predicate)
        return try? context.fetch(descriptor).first
    }

    public func mostRecent() -> Reading? {
        var descriptor = FetchDescriptor<Reading>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    public func insert(_ reading: Reading) -> Reading {
        context.insert(reading)
        save()
        return reading
    }

    public func update(_ reading: Reading) {
        save()
    }

    public func delete(_ reading: Reading) {
        context.delete(reading)
        save()
    }

    public func deleteAll() {
        for r in allReadings() { context.delete(r) }
        save()
    }

    public func deleteRange(_ range: ClosedRange<Date>) {
        for r in readings(in: range) { context.delete(r) }
        save()
    }

    public func bulkInsert(_ readings: [Reading], replacingExisting: Bool) {
        for incoming in readings {
            if replacingExisting, let existing = reading(on: incoming.date) {
                context.delete(existing)
            }
            context.insert(incoming)
        }
        save()
    }

    private func save() {
        do { try context.save() } catch { print("[Repository] save failed: \(error)") }
    }
}
