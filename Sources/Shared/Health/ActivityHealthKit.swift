import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
public final class ActivityHealthKit: ObservableObject {
    @Published public private(set) var lastSyncedAt: Date?
    public var onActivityChanged: (() -> Void)?

    private let repository: ReadingRepository

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    public init(repository: ReadingRepository) {
        self.repository = repository
    }

    public var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    public func requestAuthorization() async -> Bool {
        #if canImport(HealthKit)
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: Set(activityTypes()))
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    public func startObservingIfAuthorized() async {
        #if canImport(HealthKit)
        guard isAvailable else { return }

        for type in activityTypes() {
            do {
                try await store.enableBackgroundDelivery(for: type, frequency: .hourly)
            } catch {
                print("[ActivityHK] enableBackgroundDelivery failed for \(type.identifier): \(error)")
            }

            let observer = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                completion()
                guard error == nil else { return }
                Task { @MainActor in
                    let since = Calendar.current.date(byAdding: .day, value: -14, to: Date())
                    _ = await self?.backfillHistory(since: since)
                }
            }
            store.execute(observer)
        }
        #endif
    }

    @discardableResult
    public func backfillHistory(since: Date? = nil) async -> Int {
        #if canImport(HealthKit)
        guard isAvailable else { return 0 }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: since ?? calendar.date(byAdding: .year, value: -2, to: Date()) ?? Date())
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()

        async let steps = dailyQuantities(
            identifier: .stepCount,
            unit: .count(),
            start: start,
            end: end,
            calendar: calendar
        )
        async let energy = dailyQuantities(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: end,
            calendar: calendar
        )
        async let exercise = dailyQuantities(
            identifier: .appleExerciseTime,
            unit: .minute(),
            start: start,
            end: end,
            calendar: calendar
        )

        let (stepValues, energyValues, exerciseValues) = await (steps, energy, exercise)
        let allDays = Set(stepValues.keys).union(energyValues.keys).union(exerciseValues.keys)

        let activities = allDays.compactMap { day -> DailyActivity? in
            let stepCount = Int((stepValues[day] ?? 0).rounded())
            let activeEnergy = energyValues[day]
            let exerciseMinutes = exerciseValues[day].map { Int($0.rounded()) }

            guard stepCount > 0 || activeEnergy != nil || exerciseMinutes != nil else { return nil }
            return DailyActivity(
                day: day,
                steps: stepCount,
                activeEnergyKcal: activeEnergy,
                exerciseMinutes: exerciseMinutes,
                source: "Apple Health",
                lastUpdated: Date()
            )
        }

        repository.bulkInsertActivity(activities, replacingExisting: true)
        lastSyncedAt = Date()
        if !activities.isEmpty {
            onActivityChanged?()
        }
        return activities.count
        #else
        return 0
        #endif
    }

    #if canImport(HealthKit)
    private func activityTypes() -> [HKQuantityType] {
        [
            HKQuantityType.quantityType(forIdentifier: .stepCount),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime),
        ].compactMap { $0 }
    }

    private func dailyQuantities(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            var anchorComponents = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day], from: start)
            anchorComponents.hour = 0
            anchorComponents.minute = 0
            anchorComponents.second = 0
            let anchor = calendar.date(from: anchorComponents) ?? start

            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var values: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    let value = quantity.doubleValue(for: unit)
                    guard value > 0 else { return }
                    values[calendar.startOfDay(for: statistics.startDate)] = value
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
    #endif
}
