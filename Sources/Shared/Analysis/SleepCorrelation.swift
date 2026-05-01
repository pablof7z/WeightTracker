import Foundation

public struct SleepWeightCorrelation: Sendable {
    public let n: Int
    public let spearmanRho: Double
    public let ciLow: Double
    public let ciHigh: Double

    public init(n: Int, spearmanRho: Double, ciLow: Double, ciHigh: Double) {
        self.n = n
        self.spearmanRho = spearmanRho
        self.ciLow = ciLow
        self.ciHigh = ciHigh
    }
}

public enum SleepCorrelation {
    /// Pair each reading with the sleep night `lagDays` days before. Returns nil if fewer than 30 pairs.
    /// Returns Spearman rho with bootstrap 95% CI (1000 resamples).
    public static func correlate(
        readings: [Reading],
        nights: [SleepNight],
        lagDays: Int = 0
    ) -> SleepWeightCorrelation? {
        // Index nights by dayStart for O(1) lookup.
        var nightByDay: [Date: SleepNight] = [:]
        for n in nights {
            nightByDay[Reading.dayStart(of: n.nightDate)] = n
        }

        var weights: [Double] = []
        var hours: [Double] = []
        weights.reserveCapacity(readings.count)
        hours.reserveCapacity(readings.count)

        for r in readings {
            let target = r.date.addingTimeInterval(-Double(lagDays) * 86_400)
            let key = Reading.dayStart(of: target)
            guard let night = nightByDay[key] else { continue }
            weights.append(r.weightKg)
            hours.append(night.asleepHours)
        }

        guard weights.count >= 30 else { return nil }

        let rho = spearman(weights, hours) ?? 0
        let (lo, hi) = bootstrapCI(weights: weights, hours: hours, iterations: 1000)
        return SleepWeightCorrelation(n: weights.count, spearmanRho: rho, ciLow: lo, ciHigh: hi)
    }

    // MARK: - Math

    static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let rx = ranks(x)
        let ry = ranks(y)
        return pearson(rx, ry)
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let n = Double(x.count)
        let mx = x.reduce(0, +) / n
        let my = y.reduce(0, +) / n
        var num = 0.0
        var dx2 = 0.0
        var dy2 = 0.0
        for i in 0..<x.count {
            let a = x[i] - mx
            let b = y[i] - my
            num += a * b
            dx2 += a * a
            dy2 += b * b
        }
        let denom = (dx2 * dy2).squareRoot()
        guard denom > 0 else { return 0 }
        return num / denom
    }

    /// Tied ranks use average rank.
    static func ranks(_ values: [Double]) -> [Double] {
        let indexed = values.enumerated().map { (idx: $0.offset, val: $0.element) }
        let sorted = indexed.sorted { $0.val < $1.val }
        var result = [Double](repeating: 0, count: values.count)
        var i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count && sorted[j + 1].val == sorted[i].val {
                j += 1
            }
            // ranks i..j (1-based: i+1 .. j+1), average them
            let avg = Double((i + 1) + (j + 1)) / 2.0
            for k in i...j {
                result[sorted[k].idx] = avg
            }
            i = j + 1
        }
        return result
    }

    private static func bootstrapCI(
        weights: [Double],
        hours: [Double],
        iterations: Int
    ) -> (Double, Double) {
        let n = weights.count
        guard n >= 2 else { return (0, 0) }
        var rhos: [Double] = []
        rhos.reserveCapacity(iterations)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<iterations {
            var sx = [Double]()
            var sy = [Double]()
            sx.reserveCapacity(n)
            sy.reserveCapacity(n)
            for _ in 0..<n {
                let idx = Int.random(in: 0..<n, using: &rng)
                sx.append(weights[idx])
                sy.append(hours[idx])
            }
            if let r = spearman(sx, sy) {
                rhos.append(r)
            }
        }
        rhos.sort()
        guard !rhos.isEmpty else { return (0, 0) }
        let loIdx = Int((Double(rhos.count) * 0.025).rounded(.down))
        let hiIdx = min(rhos.count - 1, Int((Double(rhos.count) * 0.975).rounded(.down)))
        return (rhos[loIdx], rhos[hiIdx])
    }
}
