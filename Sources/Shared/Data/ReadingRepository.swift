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

    // Sleep
    func allSleepNights() -> [SleepNight]
    func sleepNight(on date: Date) -> SleepNight?
    func bulkInsertSleep(_ nights: [SleepNight], replacingExisting: Bool)

    // Daily activity
    func allDailyActivities() -> [DailyActivity]
    func dailyActivities(in range: ClosedRange<Date>) -> [DailyActivity]
    func dailyActivity(on date: Date) -> DailyActivity?
    func bulkInsertActivity(_ activities: [DailyActivity], replacingExisting: Bool)
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
        // Match within ±12h of the day-start rather than requiring an exact
        // timestamp. Readings are stored at `dayStart` in the device's current
        // timezone, so a near-midnight reading saved under a different
        // timezone/DST offset lands on a slightly different instant; exact
        // equality used to miss it and let duplicates accumulate. Distinct
        // calendar days are 24h apart, so a 24h-wide window centered on midnight
        // still resolves to a single day; pick the reading nearest the boundary.
        let day = Reading.dayStart(of: date)
        let lo = day.addingTimeInterval(-12 * 3600)
        let hi = day.addingTimeInterval(12 * 3600)
        let predicate = #Predicate<Reading> { $0.date > lo && $0.date < hi }
        let descriptor = FetchDescriptor<Reading>(predicate: predicate)
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.min {
            abs($0.date.timeIntervalSince(day)) < abs($1.date.timeIntervalSince(day))
        }
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

    // MARK: - Sleep

    public func allSleepNights() -> [SleepNight] {
        let descriptor = FetchDescriptor<SleepNight>(sortBy: [SortDescriptor(\.nightDate, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func sleepNight(on date: Date) -> SleepNight? {
        let key = Reading.dayStart(of: date)
        let predicate = #Predicate<SleepNight> { $0.nightDate == key }
        let descriptor = FetchDescriptor<SleepNight>(predicate: predicate)
        return try? context.fetch(descriptor).first
    }

    public func bulkInsertSleep(_ nights: [SleepNight], replacingExisting: Bool) {
        for incoming in nights {
            if let existing = sleepNight(on: incoming.nightDate) {
                if replacingExisting {
                    context.delete(existing)
                } else {
                    continue
                }
            }
            context.insert(incoming)
        }
        save()
    }

    // MARK: - Daily activity

    public func allDailyActivities() -> [DailyActivity] {
        let descriptor = FetchDescriptor<DailyActivity>(sortBy: [SortDescriptor(\.day, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func dailyActivities(in range: ClosedRange<Date>) -> [DailyActivity] {
        let lo = Reading.dayStart(of: range.lowerBound)
        let hi = Reading.dayStart(of: range.upperBound)
        let predicate = #Predicate<DailyActivity> { $0.day >= lo && $0.day <= hi }
        let descriptor = FetchDescriptor<DailyActivity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.day, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func dailyActivity(on date: Date) -> DailyActivity? {
        let key = Reading.dayStart(of: date)
        let predicate = #Predicate<DailyActivity> { $0.day == key }
        let descriptor = FetchDescriptor<DailyActivity>(predicate: predicate)
        return try? context.fetch(descriptor).first
    }

    public func bulkInsertActivity(_ activities: [DailyActivity], replacingExisting: Bool) {
        for incoming in activities {
            if let existing = dailyActivity(on: incoming.day) {
                if replacingExisting {
                    context.delete(existing)
                } else {
                    continue
                }
            }
            context.insert(incoming)
        }
        save()
    }

    private func save() {
        do { try context.save() } catch { print("[Repository] save failed: \(error)") }
    }
}

/// One-time cleanup for the duplicate-per-day readings created by an earlier
/// HealthKit round-trip: a manual reading was written to Apple Health, then the
/// app re-imported its own sample as a separate `.healthKit` reading. A
/// daylight-saving shift moved the bucketed day-start by an hour, so the two
/// records landed on different instants and the exact-match dedup missed them.
///
/// The going-forward fix lives in `HealthKitManager.ingest` (skip our own
/// samples when the day already exists) and `reading(on:)` (match within ±12h).
/// This collapses the duplicates already in the store.
@MainActor
public enum ReadingDeduper {
    private static let didRunKey = "readings.dedupe.healthkitRoundtrip.v1"

    /// Runs the cleanup at most once. Safe to call on every launch.
    public static func runIfNeeded(_ repository: ReadingRepository) {
        guard !UserDefaults.standard.bool(forKey: didRunKey) else { return }
        let removed = dedupe(repository)
        UserDefaults.standard.set(true, forKey: didRunKey)
        if removed > 0 { print("[ReadingDeduper] removed \(removed) duplicate readings") }
    }

    /// Collapses readings within 12h of each other (the same day, even across a
    /// DST boundary) to a single record, preferring a user-entered reading over
    /// a HealthKit-imported one, then the most recent. Returns the number
    /// deleted. Exposed for tests / manual re-runs.
    @discardableResult
    public static func dedupe(_ repository: ReadingRepository) -> Int {
        let all = repository.allReadings().sorted { $0.date < $1.date }
        guard all.count > 1 else { return 0 }

        // Cluster by proximity: consecutive readings less than 12h apart belong
        // to the same day. Distinct days are 24h apart, so they never merge.
        var clusters: [[Reading]] = []
        for r in all {
            if let last = clusters.last?.last,
               r.date.timeIntervalSince(last.date) < 12 * 3600 {
                clusters[clusters.count - 1].append(r)
            } else {
                clusters.append([r])
            }
        }

        var removed = 0
        for cluster in clusters where cluster.count > 1 {
            guard let keep = cluster.max(by: { Self.rank($0) < Self.rank($1) }) else { continue }
            for r in cluster where r.id != keep.id {
                repository.delete(r)
                removed += 1
            }
        }
        return removed
    }

    /// Higher rank wins: a user-entered reading beats a HealthKit one; among
    /// equals, the newer timestamp wins.
    private static func rank(_ r: Reading) -> (Int, TimeInterval) {
        (r.source != .healthKit ? 1 : 0, r.date.timeIntervalSince1970)
    }
}
