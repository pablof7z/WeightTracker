import Foundation
import SwiftUI

@MainActor
final class TrendsViewModel: ObservableObject {

    struct DeltaPoint {
        let label: String
        let valueLb: Double?
    }

    @Published private(set) var readings: [Reading] = []
    @Published private(set) var clusters: [Cluster] = []
    @Published private(set) var gaps: [Gap] = []
    @Published private(set) var activeCluster: Cluster?
    @Published private(set) var activeGap: Gap?
    @Published private(set) var mostRecent: Reading?
    @Published private(set) var eras: [EraStats] = []

    func reload(repository: ReadingRepository) {
        let all = repository.allReadings()
        self.readings = all
        self.mostRecent = repository.mostRecent()
        let detected = ClusterDetector.clusters(from: all)
        self.clusters = detected
        self.activeCluster = ClusterDetector.activeCluster(in: detected)
        let gs = GapAnalyzer.gaps(between: detected, readings: all)
        self.gaps = gs
        self.activeGap = GapAnalyzer.activeGap(clusters: detected, lastReading: mostRecent)
        self.eras = EraSummary.compute(readings: all, gaps: gs)
    }

    // MARK: - Right Now deltas

    /// Returns 7-day, 30-day, and year-over-year delta in lbs (signed)
    /// computed against the closest reading at-or-before the target date.
    func deltas(now: Date = Date()) -> [DeltaPoint] {
        let cal = Calendar.current
        let recent = mostRecent
        let recentLb = recent.map { UnitConvert.kgToLb($0.weightKg) }

        func deltaFor(daysAgo: Int, label: String) -> DeltaPoint {
            guard let recentLb,
                  let target = cal.date(byAdding: .day, value: -daysAgo, to: now),
                  let baseline = closestReading(onOrBefore: target)
            else { return DeltaPoint(label: label, valueLb: nil) }
            let baseLb = UnitConvert.kgToLb(baseline.weightKg)
            return DeltaPoint(label: label, valueLb: recentLb - baseLb)
        }

        return [
            deltaFor(daysAgo: 7, label: "7-day"),
            deltaFor(daysAgo: 30, label: "30-day"),
            deltaFor(daysAgo: 365, label: "Year-over-year")
        ]
    }

    private func closestReading(onOrBefore date: Date) -> Reading? {
        readings.last { $0.date <= date }
    }

    // MARK: - Active state messaging

    var clusterDaysIn: Int? {
        guard let c = activeCluster else { return nil }
        return Calendar.current.dateComponents([.day], from: c.startDate, to: Date()).day
    }

    var clusterDownLb: Double? {
        guard let c = activeCluster, let last = mostRecent else { return nil }
        let startKg = c.readingIDs.first.flatMap { id in
            readings.first(where: { $0.id == id })?.weightKg
        } ?? c.meanWeightKg
        return UnitConvert.kgToLb(startKg - last.weightKg)
    }

    var gapDaysSinceLast: Int? {
        guard let last = mostRecent else { return nil }
        return Calendar.current.dateComponents([.day], from: last.date, to: Date()).day
    }

    var estimatedDriftLb: Double? {
        guard let last = mostRecent, let days = gapDaysSinceLast else { return nil }
        let est = DriftEstimator.estimateCurrentWeightLb(
            lastReadingKg: last.weightKg,
            daysSinceLast: days,
            historicalGaps: gaps
        )
        return est - UnitConvert.kgToLb(last.weightKg)
    }

    // MARK: - Trend line for chart

    var meanGapDriftLb: Double {
        guard !gaps.isEmpty else { return 0 }
        return gaps.map { $0.driftLb }.reduce(0, +) / Double(gaps.count)
    }
}
