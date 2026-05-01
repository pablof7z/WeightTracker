import Foundation

public enum HistoricalCutDetector {

    private static let minDurationDays: Int = 10
    private static let minRateLbPerWeek: Double = 0.5

    public static func detect(in clusters: [Cluster], readings: [Reading]) -> [HistoricalCut] {
        guard !clusters.isEmpty, !readings.isEmpty else { return [] }
        let byID: [UUID: Reading] = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })
        let cal = Calendar.current
        var results: [HistoricalCut] = []

        for cluster in clusters {
            let clusterReadings = cluster.readingIDs
                .compactMap { byID[$0] }
                .sorted { $0.date < $1.date }
            guard clusterReadings.count >= 2 else { continue }

            let n = clusterReadings.count
            var bestStart = -1
            var bestEnd = -1
            var bestDays = 0

            // Find longest sub-range satisfying constraints (greedy: try each start, extend max end)
            for i in 0..<(n - 1) {
                for j in (i + 1)..<n {
                    let a = clusterReadings[i]
                    let b = clusterReadings[j]
                    let days = cal.dateComponents([.day], from: a.date, to: b.date).day ?? 0
                    guard days >= minDurationDays else { continue }
                    let lossKg = a.weightKg - b.weightKg
                    guard lossKg > 0 else { continue }
                    let lossLb = UnitConvert.kgToLb(lossKg)
                    let weeks = Double(days) / 7.0
                    let ratePerWeek = lossLb / weeks
                    guard ratePerWeek >= minRateLbPerWeek else { continue }
                    if days > bestDays {
                        bestDays = days
                        bestStart = i
                        bestEnd = j
                    }
                }
            }

            if bestStart >= 0, bestEnd > bestStart {
                let a = clusterReadings[bestStart]
                let b = clusterReadings[bestEnd]
                let days = cal.dateComponents([.day], from: a.date, to: b.date).day ?? 0
                let lossKg = a.weightKg - b.weightKg
                let weeks = max(1.0, Double(days)) / 7.0
                let rateKgPerWeek = lossKg / weeks
                results.append(HistoricalCut(
                    startDate: a.date,
                    endDate: b.date,
                    startWeightKg: a.weightKg,
                    endWeightKg: b.weightKg,
                    totalLossKg: lossKg,
                    avgRateKgPerWeek: rateKgPerWeek,
                    durationDays: days
                ))
            }
        }
        return results
    }
}
