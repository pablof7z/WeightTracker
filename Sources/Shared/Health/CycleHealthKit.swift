import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
public final class CycleHealthKit: ObservableObject {
    @Published public private(set) var lastSyncedAt: Date?

    private let storageKey = "cycle.starts.v1"
    private let backfillMonths = 12
    private let newCycleGapDays = 14

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    public init() {}

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
        let menstrual = HKCategoryType(.menstrualFlow)
        do {
            try await store.requestAuthorization(toShare: [], read: [menstrual])
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    @discardableResult
    public func fetchAndStoreCycleStarts() async -> [Date] {
        #if canImport(HealthKit)
        guard isAvailable else { return loadStoredCycleStarts() }
        let menstrual = HKCategoryType(.menstrualFlow)
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -backfillMonths, to: Date()) ?? Date.distantPast
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)

        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: menstrual,
                predicate: predicate,
                limit: 0,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        let starts = Self.cycleStarts(from: samples, gapDays: newCycleGapDays, calendar: calendar)
        persist(starts)
        lastSyncedAt = Date()
        return starts
        #else
        return loadStoredCycleStarts()
        #endif
    }

    public func fetchAndStoreCycleStartsIfEnabled() async {
        guard UserDefaults.standard.bool(forKey: AppPrefKey.cycleAdjustmentEnabled) else { return }
        _ = await fetchAndStoreCycleStarts()
    }

    public func loadStoredCycleStarts() -> [Date] {
        guard let raw = UserDefaults.standard.array(forKey: storageKey) as? [Double] else { return [] }
        return raw.map { Date(timeIntervalSince1970: $0) }.sorted()
    }

    private func persist(_ starts: [Date]) {
        let raw = starts.map { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(raw, forKey: storageKey)
    }

    #if canImport(HealthKit)
    static func cycleStarts(from samples: [HKCategorySample], gapDays: Int, calendar: Calendar) -> [Date] {
        let activeFlowDays = samples
            .filter { isActiveFlow($0) }
            .map { calendar.startOfDay(for: $0.startDate) }
        let uniqueDays = Array(Set(activeFlowDays)).sorted()
        guard !uniqueDays.isEmpty else { return [] }

        var starts: [Date] = [uniqueDays[0]]
        for i in 1..<uniqueDays.count {
            let prior = uniqueDays[i - 1]
            let current = uniqueDays[i]
            let gap = calendar.dateComponents([.day], from: prior, to: current).day ?? 0
            if gap > gapDays {
                starts.append(current)
            }
        }
        return starts
    }

    private static func isActiveFlow(_ sample: HKCategorySample) -> Bool {
        guard let flow = HKCategoryValueMenstrualFlow(rawValue: sample.value) else { return false }
        switch flow {
        case .light, .medium, .heavy:
            return true
        case .unspecified, .none:
            return false
        @unknown default:
            return false
        }
    }
    #endif
}
