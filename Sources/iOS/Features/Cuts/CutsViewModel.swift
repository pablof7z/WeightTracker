import Foundation
import SwiftUI

@MainActor
final class CutsViewModel: ObservableObject {
    @Published var activeCut: ActiveCut?
    @Published var historicalCuts: [HistoricalCut] = []
    @Published var mostRecentReading: Reading?
    @Published var allReadings: [Reading] = []
    @Published var projection: CutProjectionResult?

    private let services: AppServices

    init(services: AppServices = .shared) {
        self.services = services
    }

    func reload() {
        activeCut = ActiveCutStore.load()
        let readings = services.repository.allReadings()
        allReadings = readings
        mostRecentReading = readings.last
        let clusters = ClusterDetector.clusters(from: readings)
        let detected = HistoricalCutDetector.detect(in: clusters, readings: readings)
        historicalCuts = detected.sorted { $0.startDate > $1.startDate }
        projection = CutProjection.project(active: activeCut, readings: readings, historicalCuts: detected)
    }

    func startCut(_ cut: ActiveCut) async {
        ActiveCutStore.save(cut)
        activeCut = cut
        await services.notifications.scheduleEvaluatedTriggers()
    }

    func updateCut(_ cut: ActiveCut) async {
        ActiveCutStore.save(cut)
        activeCut = cut
        await services.notifications.scheduleEvaluatedTriggers()
    }

    func markDone() async {
        ActiveCutStore.save(nil)
        activeCut = nil
        await services.notifications.scheduleEvaluatedTriggers()
        reload()
    }

    // MARK: - Active cut metrics

    /// Current weight from the most recent reading (kg).
    var currentWeightKg: Double? { mostRecentReading?.weightKg }

    /// Actual rate of loss in lb/week from start to today.
    func actualRateLbPerWeek(now: Date = Date()) -> Double? {
        guard let cut = activeCut, let current = currentWeightKg else { return nil }
        let elapsed = max(1, cut.daysElapsed(now: now))
        let lossKg = cut.startWeightKg - current
        let weeks = Double(elapsed) / 7.0
        guard weeks > 0 else { return nil }
        return UnitConvert.kgToLb(lossKg) / weeks
    }

    /// Needed rate of loss in lb/week from today to target end date.
    func neededRateLbPerWeek(now: Date = Date()) -> Double? {
        guard let cut = activeCut, let current = currentWeightKg else { return nil }
        let remaining = max(1, cut.daysRemaining(now: now))
        let remainingLossKg = current - cut.targetWeightKg
        let weeks = Double(remaining) / 7.0
        guard weeks > 0 else { return nil }
        return UnitConvert.kgToLb(remainingLossKg) / weeks
    }

    enum CutStatus { case onTrack, behind, reversed }

    /// Compare actual vs needed rate. Reversed = gaining; behind = positive but below needed.
    func status(now: Date = Date()) -> CutStatus? {
        guard let actual = actualRateLbPerWeek(now: now),
              let needed = neededRateLbPerWeek(now: now) else { return nil }
        if actual <= 0 { return .reversed }
        if actual + 0.05 < needed { return .behind }
        return .onTrack
    }

    /// Projected end weight if we continue at the actual rate (kg).
    func projectedEndWeightKg(now: Date = Date()) -> Double? {
        guard let cut = activeCut, let current = currentWeightKg,
              let actualLb = actualRateLbPerWeek(now: now) else { return nil }
        let remaining = max(0, cut.daysRemaining(now: now))
        let weeks = Double(remaining) / 7.0
        let projectedLossKg = UnitConvert.lbToKg(actualLb * weeks)
        return current - projectedLossKg
    }

    /// Age (in years rounded down) at the start of a historical cut. Requires birthdate;
    /// since none is stored, we return the elapsed years from the cut start to today as a
    /// proxy "age at the time" placeholder. Spec wording: "age at the time" — display the
    /// duration since that cut.
    func yearsAgo(of date: Date, now: Date = Date()) -> Int {
        let comps = Calendar.current.dateComponents([.year], from: date, to: now)
        return max(0, comps.year ?? 0)
    }
}
