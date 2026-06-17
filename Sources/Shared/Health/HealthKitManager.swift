import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
public final class HealthKitManager: ObservableObject {
    public enum AuthState { case notRequested, authorized, denied, unavailable }

    @Published public private(set) var authState: AuthState = .notRequested
    public var onReadingsChanged: (() -> Void)?

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
        guard isAvailable else {
            authState = .unavailable
            return false
        }
        let bodyMass = HKQuantityType(.bodyMass)
        do {
            try await store.requestAuthorization(toShare: [bodyMass], read: [bodyMass])
            authState = .authorized
            return true
        } catch {
            authState = .denied
            return false
        }
        #else
        authState = .unavailable
        return false
        #endif
    }

    public func startObservingIfAuthorized() async {
        #if canImport(HealthKit)
        guard isAvailable else { return }
        let bodyMass = HKQuantityType(.bodyMass)
        let status = store.authorizationStatus(for: bodyMass)
        guard status == .sharingAuthorized else { return }
        authState = .authorized

        // Background delivery
        do {
            try await store.enableBackgroundDelivery(for: bodyMass, frequency: .immediate)
        } catch {
            print("[HK] enableBackgroundDelivery failed: \(error)")
        }

        // Observer
        let observer = HKObserverQuery(sampleType: bodyMass, predicate: nil) { [weak self] _, completion, error in
            // Always complete observer immediately; perform ingest async
            completion()
            guard error == nil else { return }
            Task { @MainActor in
                await self?.fetchRecentSamples()
            }
        }
        store.execute(observer)

        // Initial backfill
        await fetchRecentSamples()
        #endif
    }

    public func replayHistory() async -> Int {
        #if canImport(HealthKit)
        guard isAvailable else { return 0 }
        let bodyMass = HKQuantityType(.bodyMass)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMass,
                predicate: nil,
                limit: 0,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { [weak self] _, samples, _ in
                Task { @MainActor in
                    let count = await self?.ingest(samples ?? []) ?? 0
                    continuation.resume(returning: count)
                }
            }
            store.execute(query)
        }
        #else
        return 0
        #endif
    }

    public func writeReading(_ reading: Reading) async {
        #if canImport(HealthKit)
        guard isAvailable else { return }
        let bodyMass = HKQuantityType(.bodyMass)
        let qty = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: reading.weightKg)
        let sample = HKQuantitySample(type: bodyMass, quantity: qty, start: reading.date, end: reading.date)
        do { try await store.save(sample) } catch { print("[HK] save failed: \(error)") }
        #endif
    }

    /// Deletes the Apple Health body-mass sample(s) THIS app wrote for a given
    /// day and value. Called when a reading is deleted or edited in-app so the
    /// matching Health sample doesn't linger (and can't be re-imported). We can
    /// only delete our own samples, which is exactly what we want.
    public func deleteSample(weightKg: Double, on date: Date) async {
        #if canImport(HealthKit)
        guard isAvailable else { return }
        let bodyMass = HKQuantityType(.bodyMass)
        let day = Reading.dayStart(of: date)
        let lo = day.addingTimeInterval(-12 * 3600)
        let hi = day.addingTimeInterval(12 * 3600)
        let datePredicate = HKQuery.predicateForSamples(withStart: lo, end: hi, options: [])
        let mine = HKQuery.predicateForObjects(from: .default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, mine])
        let samples: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: bodyMass, predicate: predicate, limit: 0, sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: s ?? [])
            }
            store.execute(q)
        }
        let targets = samples
            .compactMap { $0 as? HKQuantitySample }
            .filter { abs($0.quantity.doubleValue(for: .gramUnit(with: .kilo)) - weightKg) < 0.05 }
        guard !targets.isEmpty else { return }
        do { try await store.delete(targets) } catch { print("[HK] delete failed: \(error)") }
        #endif
    }

    private func fetchRecentSamples() async {
        #if canImport(HealthKit)
        let bodyMass = HKQuantityType(.bodyMass)
        let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: oneYearAgo, end: nil)
        let samples: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: bodyMass, predicate: predicate, limit: 0, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples ?? [])
            }
            store.execute(q)
        }
        _ = await ingest(samples)
        #endif
    }

    @discardableResult
    private func ingest(_ samples: [Any]) async -> Int {
        #if canImport(HealthKit)
        var inserted = 0
        var changed = false
        // Most-recent first: when multiple HK sources exist for the same day,
        // the latest timestamp takes precedence over earlier ones.
        let sorted = samples
            .compactMap { $0 as? HKQuantitySample }
            .sorted { $0.startDate > $1.startDate }
        // Bundle prefix that identifies samples THIS app wrote (iOS app, watch
        // app, extensions). Derived from the shared app-group id.
        let ownBundlePrefix = AppGroup.identifier.replacingOccurrences(of: "group.", with: "")
        for sample in sorted {
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            let date = sample.startDate
            let isOwnSample = sample.sourceRevision.source.bundleIdentifier.hasPrefix(ownBundlePrefix)

            if let existing = repository.reading(on: date) {
                // Our own previously-written sample being observed back. The
                // reading already lives in the local store, so never re-import
                // it — this is the round-trip that created duplicate records
                // once a DST shift moved the bucketed day-start by an hour and
                // the same-day match missed.
                if isOwnSample { continue }
                if existing.source != .healthKit {
                    // User entered this reading in the app (manual/watch/import).
                    // Never overwrite with an HK sample — avoids rounding roundtrips
                    // and interference from scales or other health apps.
                    continue
                }
                // HK-sourced reading: update if the value changed meaningfully.
                if abs(existing.weightKg - kg) > 0.001 {
                    existing.weightKg = kg
                    existing.deviceName = sample.sourceRevision.source.name
                    repository.update(existing)
                    changed = true
                }
                continue
            }
            // No local reading for this day — import it. This still covers our
            // own samples after a reinstall (no iCloud sync, so Health is the
            // only backup), as well as external scales / other health apps.
            let reading = Reading(
                date: date,
                weightKg: kg,
                source: .healthKit,
                deviceName: sample.sourceRevision.source.name
            )
            repository.insert(reading)
            inserted += 1
            changed = true
        }
        if changed {
            onReadingsChanged?()
        }
        return inserted
        #else
        return 0
        #endif
    }
}
