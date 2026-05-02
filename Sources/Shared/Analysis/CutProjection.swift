import Foundation

// MARK: - Public result type

/// Variance-aware projection result for the active cut.
///
/// The avg path is built from real historical residuals via a circular block
/// bootstrap (block length 7), so the line shows the *kind* of week-to-week
/// wiggle that historically happened — not a deterministic straight line and
/// not a smoothed curve. Best/worst are straight rays bracketing it.
public struct CutProjectionResult: Sendable {
    public let anchorDate: Date
    public let anchorKg: Double
    public let isTargetReached: Bool
    public let qualifyingHistoricalCount: Int
    /// nil iff `isTargetReached` (no rays drawn in that case).
    public let bestEndKg: Double?
    /// Length N+1, includes anchor at index 0. Empty if `isTargetReached`.
    public let avgPath: [(Date, Double)]
    /// nil iff `isTargetReached`.
    public let worstEndKg: Double?
    public let targetWeightKg: Double
    public let targetEndDate: Date

    public init(
        anchorDate: Date,
        anchorKg: Double,
        isTargetReached: Bool,
        qualifyingHistoricalCount: Int,
        bestEndKg: Double?,
        avgPath: [(Date, Double)],
        worstEndKg: Double?,
        targetWeightKg: Double,
        targetEndDate: Date
    ) {
        self.anchorDate = anchorDate
        self.anchorKg = anchorKg
        self.isTargetReached = isTargetReached
        self.qualifyingHistoricalCount = qualifyingHistoricalCount
        self.bestEndKg = bestEndKg
        self.avgPath = avgPath
        self.worstEndKg = worstEndKg
        self.targetWeightKg = targetWeightKg
        self.targetEndDate = targetEndDate
    }
}

// MARK: - Deterministic PRNG

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}

// MARK: - CutProjection

public enum CutProjection {

    // Memoized last computation (cheap key, identity-of-inputs).
    // Wrapped in a tiny mutex so it's safe under Swift 6 strict concurrency
    // even though the surrounding function is `static` (non-isolated).
    private final class Cache: @unchecked Sendable {
        var key: String?
        var result: CutProjectionResult?
        let lock = NSLock()
    }
    private static let cache = Cache()

    /// Compute the variance-aware projection for an active cut.
    ///
    /// Returns nil when there is no active cut, or when the target end date
    /// is in the past (N < 1 day).
    public static func project(
        active: ActiveCut?,
        readings: [Reading],
        historicalCuts: [HistoricalCut],
        now: Date = Date()
    ) -> CutProjectionResult? {
        guard let active else { return nil }

        // Step 3 — anchor weight from in-cut readings (last 7, drop max+min, mean of 5).
        let inCut = readings.filter { $0.date >= active.startDate && $0.date <= now }
        let anchorKg: Double
        let anchorDate: Date
        if let last = inCut.last {
            anchorDate = last.date
            anchorKg = anchor(from: inCut)
        } else {
            anchorDate = now
            anchorKg = active.startWeightKg
        }

        // Step 4 — projection days remaining.
        let secondsPerDay: TimeInterval = 86_400
        let rawDays = active.targetEndDate.timeIntervalSince(anchorDate) / secondsPerDay
        let N = Int(rawDays.rounded(.down))

        // Memoization key
        let lastID = inCut.last?.id.uuidString ?? "nil"
        let key = "\(lastID)|\(anchorKg)|\(active.targetEndDate.timeIntervalSince1970)|\(historicalCuts.count)|\(active.targetWeightKg)"
        cache.lock.lock()
        if cache.key == key, let cached = cache.result {
            cache.lock.unlock()
            return cached
        }
        cache.lock.unlock()

        // Step 8 — target reached guard.
        if anchorKg <= active.targetWeightKg + 0.5 {
            let result = CutProjectionResult(
                anchorDate: anchorDate,
                anchorKg: anchorKg,
                isTargetReached: true,
                qualifyingHistoricalCount: historicalCuts.count,
                bestEndKg: nil,
                avgPath: [],
                worstEndKg: nil,
                targetWeightKg: active.targetWeightKg,
                targetEndDate: active.targetEndDate
            )
            cache.lock.lock()
            cache.key = key
            cache.result = result
            cache.lock.unlock()
            return result
        }

        guard N >= 1 else { return nil }

        // Steps 1 & 2 — slopes (best/avg/worst, in %BW per week, negative = losing).
        let (bestPct, avgPct, worstPct) = slopes(historicalCuts: historicalCuts)

        // Steps 5 & 6 — residual pool + circular block bootstrap (avg only).
        let pool = residualPool(historicalCuts: historicalCuts, readings: readings)
        let bootstrap: [Double]
        if pool.isEmpty {
            bootstrap = Array(repeating: 0.0, count: N + 1)
        } else {
            let seedDouble = active.startDate.timeIntervalSince1970.rounded()
            let seed = UInt64(bitPattern: Int64(seedDouble))
            bootstrap = circularBlockBootstrap(pool: pool, length: N + 1, blockSize: 7, seed: seed)
        }

        // Step 7 — lines.
        let bestSlopeKgPerDay = (bestPct / 100.0) * anchorKg / 7.0
        let worstSlopeKgPerDay = (worstPct / 100.0) * anchorKg / 7.0
        let avgSlopeKgPerDay = (avgPct / 100.0) * anchorKg / 7.0

        let cap = floorCap(active: active)

        let bestEndRaw = anchorKg + bestSlopeKgPerDay * Double(N)
        let worstEndRaw = anchorKg + worstSlopeKgPerDay * Double(N)
        let bestEndKg = max(bestEndRaw, cap)
        let worstEndKg = max(worstEndRaw, cap)

        var avgPath: [(Date, Double)] = []
        avgPath.reserveCapacity(N + 1)
        for t in 0...N {
            let date = anchorDate.addingTimeInterval(Double(t) * secondsPerDay)
            let trend = anchorKg + avgSlopeKgPerDay * Double(t)
            // index 0 has no wiggle (pinned to anchor).
            let wiggle: Double = (t == 0 || pool.isEmpty) ? 0.0 : (bootstrap[t] * anchorKg)
            let raw = trend + wiggle
            // Clamp within the best/worst corridor so the avg line never escapes its bounds.
            let bestAtT = anchorKg + bestSlopeKgPerDay * Double(t)
            let worstAtT = anchorKg + worstSlopeKgPerDay * Double(t)
            let corridorLo = min(bestAtT, worstAtT)
            let corridorHi = max(bestAtT, worstAtT)
            let bounded = max(corridorLo, min(corridorHi, raw))
            avgPath.append((date, max(bounded, cap)))
        }

        let result = CutProjectionResult(
            anchorDate: anchorDate,
            anchorKg: anchorKg,
            isTargetReached: false,
            qualifyingHistoricalCount: historicalCuts.count,
            bestEndKg: bestEndKg,
            avgPath: avgPath,
            worstEndKg: worstEndKg,
            targetWeightKg: active.targetWeightKg,
            targetEndDate: active.targetEndDate
        )
        cache.lock.lock()
        cache.key = key
        cache.result = result
        cache.lock.unlock()
        return result
    }

    // MARK: - Step 1 & 2: slopes

    private static func slopes(historicalCuts: [HistoricalCut]) -> (best: Double, avg: Double, worst: Double) {
        // Step 1
        let raw: [Double] = historicalCuts.compactMap { hc in
            guard hc.startWeightKg > 0 else { return nil }
            return -abs(hc.avgRateKgPerWeek / hc.startWeightKg) * 100.0
        }
        let n = raw.count
        if n == 0 {
            // Helms 2014 priors (in %BW/wk).
            return (best: -1.0, avg: -0.7, worst: -0.3)
        }
        let sorted = raw.sorted() // ascending: most negative first = "best"
        if n >= 5 {
            let worst = mean(Array(sorted[(n - 2)...(n - 1)]))
            let best = mean(Array(sorted[0...1]))
            let avg = sorted[n / 2]
            return (best: best, avg: avg, worst: worst)
        } else {
            let worst = sorted.last ?? 0
            let best = sorted.first ?? 0
            let avg = median(sorted)
            return (best: best, avg: avg, worst: worst)
        }
    }

    private static func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    // MARK: - Step 3: anchor

    private static func anchor(from inCut: [Reading]) -> Double {
        guard !inCut.isEmpty else { return 0 }
        // last 7 readings
        let tail = Array(inCut.suffix(7))
        if tail.count < 3 {
            return tail.last?.weightKg ?? 0
        }
        let kgs = tail.map(\.weightKg)
        guard let mn = kgs.min(), let mx = kgs.max() else { return tail.last?.weightKg ?? 0 }
        // Drop one occurrence of min and one of max.
        var dropMinDone = false
        var dropMaxDone = false
        var kept: [Double] = []
        for v in kgs {
            if !dropMinDone, v == mn { dropMinDone = true; continue }
            if !dropMaxDone, v == mx { dropMaxDone = true; continue }
            kept.append(v)
        }
        guard !kept.isEmpty else { return tail.last?.weightKg ?? 0 }
        return mean(kept)
    }

    // MARK: - Step 5: residual pool

    private static func residualPool(historicalCuts: [HistoricalCut], readings: [Reading]) -> [Double] {
        guard !historicalCuts.isEmpty, !readings.isEmpty else { return [] }
        let sorted = historicalCuts.sorted(by: { $0.startDate > $1.startDate })
        let chosen: [HistoricalCut]
        if sorted.count >= 2 {
            chosen = Array(sorted.prefix(2))
        } else {
            chosen = sorted
        }

        var pool: [Double] = []
        for hc in chosen {
            let cutReadings = readings
                .filter { $0.date >= hc.startDate && $0.date <= hc.endDate }
                .sorted(by: { $0.date < $1.date })
            guard let first = cutReadings.first else { continue }
            // Trim first 14 days
            let trimStart = first.date.addingTimeInterval(14 * 86_400)
            let trimmed = cutReadings.filter { $0.date >= trimStart }
            guard trimmed.count >= 2 else { continue }

            let xs = trimmed.map { $0.date.timeIntervalSince(trimmed.first!.date) / 86_400 }
            let ys = trimmed.map(\.weightKg)
            let (slope, intercept) = ols(xs: xs, ys: ys)
            let meanY = mean(ys)
            guard meanY > 0 else { continue }
            for i in 0..<xs.count {
                let fitted = intercept + slope * xs[i]
                let residual = ys[i] - fitted
                pool.append(residual / meanY)
            }
        }
        return pool
    }

    private static func ols(xs: [Double], ys: [Double]) -> (slope: Double, intercept: Double) {
        let n = Double(xs.count)
        guard n >= 2 else { return (0, ys.first ?? 0) }
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for i in 0..<xs.count {
            let dx = xs[i] - mx
            num += dx * (ys[i] - my)
            den += dx * dx
        }
        let slope = den == 0 ? 0 : num / den
        return (slope, my - slope * mx)
    }

    // MARK: - Step 6: circular block bootstrap

    private static func circularBlockBootstrap(pool: [Double], length: Int, blockSize: Int, seed: UInt64) -> [Double] {
        guard !pool.isEmpty, length > 0 else { return [] }
        var rng = SplitMix64(seed: seed)
        var out: [Double] = []
        out.reserveCapacity(length + blockSize)
        let poolCount = pool.count
        while out.count < length {
            let start = Int(rng.next() % UInt64(poolCount))
            for k in 0..<blockSize {
                out.append(pool[(start + k) % poolCount])
            }
        }
        if out.count > length { out.removeLast(out.count - length) }
        return out
    }

    // MARK: - Cap

    private static func floorCap(active: ActiveCut) -> Double {
        max(active.targetWeightKg - 0.9, 0.85 * active.startWeightKg)
    }
}
