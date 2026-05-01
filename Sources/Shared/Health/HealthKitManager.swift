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
        for raw in samples {
            guard let sample = raw as? HKQuantitySample else { continue }
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            let date = sample.startDate

            // Dedup within 30 minutes same-day
            if let existing = repository.reading(on: date) {
                let delta = abs(existing.date.timeIntervalSince(date))
                if delta <= 1800 {
                    if existing.source != .healthKit {
                        existing.weightKg = kg
                        existing.source = .healthKit
                        existing.deviceName = sample.sourceRevision.source.name
                        repository.update(existing)
                        changed = true
                    }
                    continue
                } else {
                    repository.delete(existing)
                    changed = true
                }
            }
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
