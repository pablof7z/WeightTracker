import Foundation

/// A single projection ray from "today" forward to the cut's target end date.
public struct CutProjectionRay: Sendable {
    public let label: ProjectionLabel
    public let anchorDate: Date
    public let anchorWeightKg: Double
    public let endDate: Date
    public let endWeightKg: Double
    /// Slope in %BW per week (negative = losing). nil for the required-pace ray (computed).
    public let normalizedSlopePercentPerWeek: Double?

    public init(label: ProjectionLabel, anchorDate: Date, anchorWeightKg: Double, endDate: Date, endWeightKg: Double, normalizedSlopePercentPerWeek: Double?) {
        self.label = label
        self.anchorDate = anchorDate
        self.anchorWeightKg = anchorWeightKg
        self.endDate = endDate
        self.endWeightKg = endWeightKg
        self.normalizedSlopePercentPerWeek = normalizedSlopePercentPerWeek
    }
}

public enum ProjectionLabel: String, Sendable {
    case required   // "Needs to land on target"
    case typical    // P50 of historical normalized slopes
    case fast       // P10 of historical normalized slopes
}

public struct CutProjectionResult: Sendable {
    public let actualSmoothedAnchorKg: Double
    public let anchorDate: Date
    public let rays: [CutProjectionRay]
    /// True when user has been gaining (positive 7-day trend) during the active cut.
    public let isOffTrack: Bool
    /// Number of historical cuts that qualified (after ±50% loss-target filter).
    public let qualifyingHistoricalCount: Int
}

public enum CutProjection {
    /// Compute projection rays for an active cut.
    ///
    /// Methodology:
    /// - Anchor: 7-day trimmed mean of recent readings (falls back to last reading if sparse).
    /// - Per qualifying historical cut: linear regression slope of weightKg vs. day-since-cut-start,
    ///   then normalize by `cut.startWeightKg` to %BW/week.
    /// - "Typical" = P50 of normalized slopes; "Fast" = P10 (more negative).
    /// - "Required" = straight line from anchor to (targetEndDate, targetWeightKg).
    /// - Cap each projected end weight at `max(targetKg - 2, 0.85 * startKg)` to avoid fantasy floors.
    /// - Returns nil if no active cut, target overdue, fewer than 2 readings in cut window.
    public static func project(
        active: ActiveCut?,
        readings: [Reading],
        historicalCuts: [HistoricalCut],
        now: Date = Date()
    ) -> CutProjectionResult? {
        guard let active else { return nil }
        guard active.targetEndDate > now else { return nil }
        let inCut = readings.filter { $0.date >= active.startDate && $0.date <= now }
        guard inCut.count >= 2 else { return nil }

        // 7-day trimmed mean anchor
        let anchorKg = trimmed7DayMean(readings: inCut, now: now) ?? (inCut.last?.weightKg ?? active.startWeightKg)
        let anchorDate = inCut.last?.date ?? now

        // Off-track detection: positive slope over the last 7 days
        let recentWindow = inCut.filter { $0.date >= now.addingTimeInterval(-7 * 86_400) }
        let isOffTrack: Bool = {
            guard recentWindow.count >= 3 else { return false }
            let xs = recentWindow.map { $0.date.timeIntervalSince(recentWindow.first!.date) / 86_400 }
            let ys = recentWindow.map { $0.weightKg }
            let (slope, _) = linearRegression(xs: xs, ys: ys)
            return slope > 0
        }()

        var rays: [CutProjectionRay] = []

        // Always: required-pace line
        let requiredEnd = capped(weightKg: active.targetWeightKg, active: active)
        rays.append(CutProjectionRay(
            label: .required,
            anchorDate: anchorDate,
            anchorWeightKg: anchorKg,
            endDate: active.targetEndDate,
            endWeightKg: requiredEnd,
            normalizedSlopePercentPerWeek: nil
        ))

        // Filter historicals to comparable scale: target loss within ±50% of current cut's
        let currentLossKg = max(0.1, active.startWeightKg - active.targetWeightKg)
        let qualifying = historicalCuts.filter { hc in
            let scale = hc.totalLossKg / currentLossKg
            return scale >= 0.5 && scale <= 2.0
        }

        if !qualifying.isEmpty {
            // Per-cut normalized slope %BW/week (negative = losing). Use cut.avgRateKgPerWeek
            // (already computed) — defensible at this n; revisit per-cut regression once we have
            // cluster-aligned readings cached.
            let normalizedSlopes = qualifying.map { hc -> Double in
                let pctPerWeek = -abs(hc.avgRateKgPerWeek) / max(hc.startWeightKg, 1) * 100.0
                return pctPerWeek
            }.sorted() // most negative first

            let typicalPct = percentile(normalizedSlopes, 0.5)
            let fastPct = percentile(normalizedSlopes, 0.1)

            let daysToTarget = active.targetEndDate.timeIntervalSince(anchorDate) / 86_400

            // Typical line — always present if we have ≥1 qualifying cut
            let typicalEnd = endWeight(anchorKg: anchorKg, pctPerWeek: typicalPct, days: daysToTarget, active: active)
            rays.append(CutProjectionRay(
                label: .typical,
                anchorDate: anchorDate,
                anchorWeightKg: anchorKg,
                endDate: active.targetEndDate,
                endWeightKg: typicalEnd,
                normalizedSlopePercentPerWeek: typicalPct
            ))

            // Fast line — only when we have ≥3 qualifying cuts (band makes sense)
            if qualifying.count >= 3 {
                let fastEnd = endWeight(anchorKg: anchorKg, pctPerWeek: fastPct, days: daysToTarget, active: active)
                rays.append(CutProjectionRay(
                    label: .fast,
                    anchorDate: anchorDate,
                    anchorWeightKg: anchorKg,
                    endDate: active.targetEndDate,
                    endWeightKg: fastEnd,
                    normalizedSlopePercentPerWeek: fastPct
                ))
            }
        }

        return CutProjectionResult(
            actualSmoothedAnchorKg: anchorKg,
            anchorDate: anchorDate,
            rays: rays,
            isOffTrack: isOffTrack,
            qualifyingHistoricalCount: qualifying.count
        )
    }

    // MARK: - Helpers

    private static func endWeight(anchorKg: Double, pctPerWeek: Double, days: Double, active: ActiveCut) -> Double {
        let kgPerDay = (pctPerWeek / 100.0) * anchorKg / 7.0
        let raw = anchorKg + kgPerDay * days
        return capped(weightKg: raw, active: active)
    }

    private static func capped(weightKg: Double, active: ActiveCut) -> Double {
        let floor = max(active.targetWeightKg - 2.0 / 2.20462, 0.85 * active.startWeightKg)
        return max(weightKg, floor)
    }

    private static func trimmed7DayMean(readings: [Reading], now: Date) -> Double? {
        let window = readings.filter { $0.date >= now.addingTimeInterval(-7 * 86_400) }
        guard !window.isEmpty else { return nil }
        let kgs = window.map(\.weightKg).sorted()
        if kgs.count <= 2 { return kgs.reduce(0, +) / Double(kgs.count) }
        let trimmed = Array(kgs.dropFirst().dropLast())
        return trimmed.reduce(0, +) / Double(trimmed.count)
    }

    private static func linearRegression(xs: [Double], ys: [Double]) -> (slope: Double, intercept: Double) {
        let n = Double(xs.count)
        guard n >= 2 else { return (0, ys.first ?? 0) }
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for i in 0..<xs.count {
            num += (xs[i] - mx) * (ys[i] - my)
            den += (xs[i] - mx) * (xs[i] - mx)
        }
        let slope = den == 0 ? 0 : num / den
        let intercept = my - slope * mx
        return (slope, intercept)
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let idx = p * Double(sorted.count - 1)
        let lo = Int(idx.rounded(.down))
        let hi = Int(idx.rounded(.up))
        let frac = idx - Double(lo)
        return sorted[lo] + frac * (sorted[hi] - sorted[lo])
    }
}
