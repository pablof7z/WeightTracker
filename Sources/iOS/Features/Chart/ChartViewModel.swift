import Foundation
import SwiftUI

@MainActor
final class ChartViewModel: ObservableObject {
    @Published var readings: [Reading] = []
    @Published var clusters: [Cluster] = []
    @Published var gaps: [Gap] = []
    @Published var movingAverage: [(date: Date, kg: Double)] = []

    func reload(from repository: ReadingRepository) {
        let all = repository.allReadings()
        self.readings = all
        let cs = ClusterDetector.clusters(from: all)
        self.clusters = cs
        self.gaps = GapAnalyzer.gaps(between: cs, readings: all)
        self.movingAverage = Self.trailingAverage(readings: all, days: 30)
    }

    /// 30-day trailing average computed per reading date.
    static func trailingAverage(readings: [Reading], days: Int) -> [(date: Date, kg: Double)] {
        guard !readings.isEmpty else { return [] }
        var result: [(Date, Double)] = []
        result.reserveCapacity(readings.count)
        for (i, r) in readings.enumerated() {
            let lower = r.date.addingTimeInterval(-Double(days) * 86_400)
            var sum = 0.0
            var count = 0
            var j = i
            while j >= 0 && readings[j].date >= lower {
                sum += readings[j].weightKg
                count += 1
                j -= 1
            }
            if count > 0 {
                result.append((r.date, sum / Double(count)))
            }
        }
        return result
    }
}
