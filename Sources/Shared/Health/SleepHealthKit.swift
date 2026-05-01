import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
public final class SleepHealthKit: ObservableObject {
    @Published public private(set) var lastSyncedAt: Date?
    public var onSleepChanged: (() -> Void)?

    private let repository: ReadingRepository
    private let anchorKey = "sleepHealthKit.anchor"

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
        let sleep = HKCategoryType(.sleepAnalysis)
        do {
            try await store.requestAuthorization(toShare: [], read: [sleep])
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
        let sleep = HKCategoryType(.sleepAnalysis)
        // For read-only types, authorizationStatus is opaque (.notDetermined or .sharingDenied);
        // attempt to enable observation regardless. Errors are non-fatal.
        do {
            try await store.enableBackgroundDelivery(for: sleep, frequency: .hourly)
        } catch {
            print("[SleepHK] enableBackgroundDelivery failed: \(error)")
        }

        let anchor = loadAnchor()
        let query = HKAnchoredObjectQuery(
            type: sleep,
            predicate: nil,
            anchor: anchor,
            limit: 0
        ) { [weak self] _, samples, _, newAnchor, _ in
            Task { @MainActor in
                guard let self else { return }
                self.saveAnchor(newAnchor)
                await self.handleSamples(samples ?? [])
            }
        }
        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            Task { @MainActor in
                guard let self else { return }
                self.saveAnchor(newAnchor)
                await self.handleSamples(samples ?? [])
            }
        }
        store.execute(query)
        #endif
    }

    @discardableResult
    public func backfillHistory(since: Date? = nil) async -> Int {
        #if canImport(HealthKit)
        guard isAvailable else { return 0 }
        let sleep = HKCategoryType(.sleepAnalysis)
        let start = since ?? Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date.distantPast
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let samples: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: sleep,
                predicate: predicate,
                limit: 0,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                cont.resume(returning: samples ?? [])
            }
            store.execute(q)
        }
        return await handleSamples(samples)
        #else
        return 0
        #endif
    }

    #if canImport(HealthKit)
    @discardableResult
    private func handleSamples(_ samples: [HKSample]) async -> Int {
        let categorySamples = samples.compactMap { $0 as? HKCategorySample }
        guard !categorySamples.isEmpty else {
            lastSyncedAt = Date()
            return 0
        }
        let nights = Self.reduceSamples(categorySamples)
        repository.bulkInsertSleep(nights, replacingExisting: true)
        lastSyncedAt = Date()
        if !nights.isEmpty {
            onSleepChanged?()
        }
        return nights.count
    }

    /// Group samples by night-of-wake (endDate's local-calendar day) and reduce minutes per category.
    /// Source preference: Apple Watch > iPhone > 3rd-party. For each night, prefer the source with
    /// the most coverage (greatest cumulative duration).
    static func reduceSamples(_ samples: [HKCategorySample]) -> [SleepNight] {
        let cal = Calendar.current

        // Group samples by (nightDay, sourceID).
        struct GroupKey: Hashable { let day: Date; let sourceID: String }
        var groups: [GroupKey: [HKCategorySample]] = [:]
        for s in samples {
            let day = cal.startOfDay(for: s.endDate)
            let sourceID = s.sourceRevision.source.bundleIdentifier
            let key = GroupKey(day: day, sourceID: sourceID)
            groups[key, default: []].append(s)
        }

        // For each night, pick the best source by (preference, coverage).
        var byNight: [Date: (samples: [HKCategorySample], score: (Int, Double))] = [:]
        for (key, group) in groups {
            let coverage = group.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            let pref = sourcePreference(bundleID: key.sourceID)
            let score = (pref, coverage)
            if let existing = byNight[key.day] {
                // Prefer higher preference; if tie, higher coverage.
                if score.0 > existing.score.0 || (score.0 == existing.score.0 && score.1 > existing.score.1) {
                    byNight[key.day] = (group, score)
                }
            } else {
                byNight[key.day] = (group, score)
            }
        }

        var result: [SleepNight] = []
        result.reserveCapacity(byNight.count)
        for (day, value) in byNight {
            let night = makeNight(day: day, samples: value.samples)
            result.append(night)
        }
        result.sort { $0.nightDate < $1.nightDate }
        return result
    }

    private static func makeNight(day: Date, samples: [HKCategorySample]) -> SleepNight {
        var asleep = 0.0
        var core = 0.0
        var deep = 0.0
        var rem = 0.0
        var awake = 0.0
        var inBedStart: Date? = nil
        var inBedEnd: Date? = nil

        for s in samples {
            let minutes = s.endDate.timeIntervalSince(s.startDate) / 60.0
            guard let stage = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            switch stage {
            case .inBed:
                if inBedStart == nil || s.startDate < inBedStart! { inBedStart = s.startDate }
                if inBedEnd == nil || s.endDate > inBedEnd! { inBedEnd = s.endDate }
            case .awake:
                awake += minutes
            case .asleepCore:
                core += minutes
                asleep += minutes
            case .asleepDeep:
                deep += minutes
                asleep += minutes
            case .asleepREM:
                rem += minutes
                asleep += minutes
            case .asleepUnspecified:
                core += minutes
                asleep += minutes
            @unknown default:
                continue
            }
        }

        let productType = samples.first?.sourceRevision.productType

        return SleepNight(
            nightDate: day,
            inBedStart: inBedStart,
            inBedEnd: inBedEnd,
            asleepMinutes: Int(asleep.rounded()),
            coreMinutes: Int(core.rounded()),
            deepMinutes: Int(deep.rounded()),
            remMinutes: Int(rem.rounded()),
            awakeMinutes: Int(awake.rounded()),
            sourceProductType: productType,
            lastUpdated: Date()
        )
    }

    /// Source preference: Apple Watch (3) > iPhone (2) > Apple Health/manual (1) > 3rd-party (0).
    private static func sourcePreference(bundleID: String) -> Int {
        let id = bundleID.lowercased()
        if id.contains("com.apple.health.watch") || id.contains("com.apple.shoebox") || id.contains("watchos") {
            return 3
        }
        if id.hasPrefix("com.apple.health") {
            // Default Apple Health source — typically Watch-derived; treat as high.
            return 2
        }
        if id.hasPrefix("com.apple.") {
            return 2
        }
        return 0
    }

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor?) {
        guard let anchor else { return }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: anchorKey)
        }
    }
    #endif
}
