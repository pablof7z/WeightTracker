import Foundation

public enum ClusterDetector {

    private static let maxGapDays: Int = 14
    private static let minClusterSize: Int = 3

    public static func clusters(from readings: [Reading]) -> [Cluster] {
        guard !readings.isEmpty else { return [] }
        let sorted = readings.sorted { $0.date < $1.date }
        let cal = Calendar.current

        var groups: [[Reading]] = []
        var current: [Reading] = []
        for r in sorted {
            if let prev = current.last {
                let gap = cal.dateComponents([.day], from: prev.date, to: r.date).day ?? 0
                if gap > maxGapDays {
                    if current.count >= minClusterSize { groups.append(current) }
                    current = [r]
                } else {
                    current.append(r)
                }
            } else {
                current = [r]
            }
        }
        if current.count >= minClusterSize { groups.append(current) }

        return groups.map { makeCluster(from: $0) }
    }

    public static func activeCluster(in clusters: [Cluster], now: Date = Date()) -> Cluster? {
        guard let last = clusters.last else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: last.endDate, to: now).day ?? Int.max
        return days <= maxGapDays ? last : nil
    }

    // MARK: - Helpers

    private static func makeCluster(from readings: [Reading]) -> Cluster {
        let start = readings.first!.date
        let end = readings.last!.date
        let weights = readings.map { $0.weightKg }
        let mean = weights.reduce(0, +) / Double(weights.count)
        let minW = weights.min() ?? 0
        let maxW = weights.max() ?? 0
        let slope = leastSquaresSlope(start: start, readings: readings)
        let stddev = standardDeviation(of: weights, mean: mean)
        let stddevLb = UnitConvert.kgToLb(stddev)
        let slopeLbPerDay = UnitConvert.kgToLb(slope)

        let classification: ClusterType
        if stddevLb < 0.5 {
            classification = .flat
        } else if slopeLbPerDay < -0.05 {
            classification = .cut
        } else if slopeLbPerDay > 0.05 {
            classification = .bulk
        } else {
            classification = .maintenance
        }

        return Cluster(
            startDate: start,
            endDate: end,
            readingIDs: readings.map { $0.id },
            count: readings.count,
            meanWeightKg: mean,
            minWeightKg: minW,
            maxWeightKg: maxW,
            slopeKgPerDay: slope,
            classification: classification
        )
    }

    private static func leastSquaresSlope(start: Date, readings: [Reading]) -> Double {
        let cal = Calendar.current
        let xs: [Double] = readings.map {
            Double(cal.dateComponents([.day], from: start, to: $0.date).day ?? 0)
        }
        let ys = readings.map { $0.weightKg }
        let n = Double(readings.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let meanX = sumX / n
        let meanY = sumY / n
        var num = 0.0
        var den = 0.0
        for i in 0..<readings.count {
            let dx = xs[i] - meanX
            num += dx * (ys[i] - meanY)
            den += dx * dx
        }
        guard den > 0 else { return 0 }
        return num / den
    }

    private static func standardDeviation(of values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let sumSq = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sumSq / Double(values.count)).squareRoot()
    }
}
