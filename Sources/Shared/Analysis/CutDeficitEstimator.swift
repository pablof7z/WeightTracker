import Foundation

/// Estimates cumulative caloric deficit and recent daily deficit rate from a
/// user's weight history alone — no logged intake required.
///
/// Math (see `/tmp/cut-tracker-deficit-research-physics.md` and the UX research
/// note for the full justification):
///
/// 1. We linearly interpolate the raw scale readings onto a one-point-per-day
///    series, starting from the earliest available reading (or the cut start
///    minus a 30-day seed window, whichever is later) so the EWMA has burn-in
///    BEFORE cut start.
/// 2. We run a Hacker's Diet–style EWMA forward across that series with
///    α = 0.10 (today's reading contributes 10%, prior trend 90%).
/// 3. The cut "anchor" is the EWMA TREND value sampled on `cut.startDate`, NOT
///    the raw reading on that date. Raw start-day weights are noisy single
///    points and would distort the cumulative number forever; the trend value
///    incorporates the prior days of context.
/// 4. Cumulative deficit = `(trendAtCutStart − trendToday) × kcalPerLbBodyWeight`,
///    where the trend is converted from kg to lb at the multiplication step.
/// 5. Recent daily rate = OLS slope of the EWMA trend over the trailing 14
///    days (in lb/day) × `kcalPerLbBodyWeight`. Slope is `dWeight/dDay`; a
///    negative slope (losing weight) yields a POSITIVE deficit number.
///
/// `kcalPerLbBodyWeight = 3000` is intentionally between mixed-tissue
/// physiology (~2900) and the popular 3500 figure. Single named constant so
/// it's easy to retune later.
public enum CutDeficitEstimator {

    // MARK: - Constants

    /// Energy density per pound of body-weight change. Defensibly conservative;
    /// see the research note. Tune here, not at the call sites.
    public static let kcalPerLbBodyWeight: Double = 3000

    /// Hacker's Diet style smoothing factor. α = 0.10 means the latest reading
    /// contributes 10%, the prior trend 90%.
    public static let ewmaAlpha: Double = 0.10

    /// How many days of pre-cut readings to seed the EWMA with so the value
    /// sampled on `cut.startDate` reflects the run-up trend, not just that
    /// one day's noisy reading.
    private static let preCutSeedDays: Int = 30

    /// Trailing-window length for the daily-rate OLS regression.
    public static let dailyRateWindowDays: Int = 14

    // MARK: - Public result

    public enum CalibrationState: Equatable, Sendable {
        case active
        /// `daysRemaining` to wait before the value should be displayed.
        case calibrating(daysRemaining: Int)
        case noActiveCut
    }

    public struct Result: Sendable {
        /// Total accumulated kcal deficit since the trend value at cut start.
        /// Positive = deficit, negative = surplus.
        public let cumulativeDeficitKcal: Double?
        public let cumulativeState: CalibrationState
        /// Recent daily rate in kcal/day. Positive = deficit, negative = surplus.
        public let dailyDeficitKcalPerDay: Double?
        public let dailyRateState: CalibrationState
        /// Days since cut start (start day = 0).
        public let daysSinceCutStart: Int?
    }

    // MARK: - Entry point

    /// Compute deficit metrics for the active cut as of `asOf` (defaults to today).
    /// Returns a result whose `*State` fields reflect calibration gating; the
    /// caller decides what to render based on those.
    public static func estimate(
        activeCut: ActiveCut?,
        readings: [Reading],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> Result {
        guard let cut = activeCut else {
            return Result(
                cumulativeDeficitKcal: nil,
                cumulativeState: .noActiveCut,
                dailyDeficitKcalPerDay: nil,
                dailyRateState: .noActiveCut,
                daysSinceCutStart: nil
            )
        }

        let cutStartDay = calendar.startOfDay(for: cut.startDate)
        let today = calendar.startOfDay(for: asOf)
        let daysSinceStart = max(0, calendar.dateComponents([.day], from: cutStartDay, to: today).day ?? 0)

        // Build the daily-interpolated EWMA trend series. Seed window starts
        // at the earliest reading (or cut.startDate − preCutSeedDays).
        let trend = buildEwmaTrend(
            readings: readings,
            cutStart: cutStartDay,
            asOf: today,
            calendar: calendar
        )

        // Look up trend at cut start and today. Both keys are start-of-day.
        let trendAtCutStart = trend[cutStartDay]
        let trendToday = trend[today]

        // --- Cumulative deficit -------------------------------------------------
        // No calibration gating: show the number from day 0 if we have anchor +
        // current-day trend points. Early-cut numbers will reflect water/glycogen
        // flux — that's a known accuracy tradeoff the user explicitly accepted.
        let cumulativeKcal: Double? = {
            guard let start = trendAtCutStart, let now = trendToday else { return nil }
            // start − now in kg; positive when weight has dropped.
            let deltaLb = UnitConvert.kgToLb(start - now)
            return deltaLb * kcalPerLbBodyWeight
        }()
        let cumulativeState: CalibrationState = (cumulativeKcal == nil) ? .noActiveCut : .active

        // --- Daily rate ---------------------------------------------------------
        // Use up to 14 trailing days of trend; if we have fewer than 14 days
        // since cut start, fall back to whatever we have (minimum 2 points).
        let dailyKcal: Double? = {
            let windowDays = max(2, min(dailyRateWindowDays, daysSinceStart + 1))
            var series: [(dayIndex: Double, kg: Double)] = []
            for offset in (0..<windowDays).reversed() {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                      let kg = trend[calendar.startOfDay(for: day)] else { continue }
                series.append((Double(windowDays - 1 - offset), kg))
            }
            guard series.count >= 2 else { return nil }
            let slopeKgPerDay = olsSlope(series)
            // Negative slope (weight dropping) → positive deficit.
            let slopeLbPerDay = UnitConvert.kgToLb(slopeKgPerDay)
            return -slopeLbPerDay * kcalPerLbBodyWeight
        }()
        let dailyRateState: CalibrationState = (dailyKcal == nil) ? .noActiveCut : .active

        return Result(
            cumulativeDeficitKcal: cumulativeKcal,
            cumulativeState: cumulativeState,
            dailyDeficitKcalPerDay: dailyKcal,
            dailyRateState: dailyRateState,
            daysSinceCutStart: daysSinceStart
        )
    }

    // MARK: - EWMA trend construction

    /// Build a `[startOfDay: trendKg]` map covering at least the window from
    /// `min(earliestReading, cutStart − preCutSeedDays)` through `asOf`.
    /// Missing days are linearly interpolated between adjacent raw readings;
    /// a constant α = 0.10 EWMA is then applied left-to-right.
    static func buildEwmaTrend(
        readings: [Reading],
        cutStart: Date,
        asOf: Date,
        calendar: Calendar = .current
    ) -> [Date: Double] {
        // Collapse to one weight per calendar day (latest wins if duplicates).
        var byDay: [Date: Double] = [:]
        for r in readings {
            let d = calendar.startOfDay(for: r.date)
            byDay[d] = r.weightKg
        }
        guard !byDay.isEmpty else { return [:] }

        let sortedDays = byDay.keys.sorted()
        let earliestReading = sortedDays.first!
        let seedFloor = calendar.date(byAdding: .day, value: -preCutSeedDays, to: cutStart) ?? cutStart
        // Start the daily series at whichever is later: earliestReading vs seedFloor.
        // We don't fabricate weights before the first real reading — without that
        // data we can't seed anything anyway.
        let startDay = max(earliestReading, calendar.startOfDay(for: seedFloor))
        let endDay = max(asOf, sortedDays.last!)

        // Build the daily raw series via linear interpolation between known
        // readings. Days before the first reading or after the last reading
        // get the nearest known value.
        var dailyRaw: [(Date, Double)] = []
        var cursor = startDay
        while cursor <= endDay {
            dailyRaw.append((cursor, interpolatedKg(on: cursor, in: sortedDays, byDay: byDay)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        // EWMA forward.
        var trend: [Date: Double] = [:]
        guard let first = dailyRaw.first else { return trend }
        var ema = first.1
        trend[first.0] = ema
        for (day, raw) in dailyRaw.dropFirst() {
            ema = ewmaAlpha * raw + (1.0 - ewmaAlpha) * ema
            trend[day] = ema
        }
        return trend
    }

    private static func interpolatedKg(
        on day: Date,
        in sortedDays: [Date],
        byDay: [Date: Double]
    ) -> Double {
        if let exact = byDay[day] { return exact }
        // Find bracketing readings.
        var prev: Date?
        var next: Date?
        for d in sortedDays {
            if d <= day { prev = d } else { next = d; break }
        }
        switch (prev, next) {
        case let (p?, n?):
            let pVal = byDay[p]!
            let nVal = byDay[n]!
            let total = n.timeIntervalSince(p)
            guard total > 0 else { return pVal }
            let t = day.timeIntervalSince(p) / total
            return pVal + t * (nVal - pVal)
        case let (p?, nil):
            return byDay[p]!
        case let (nil, n?):
            return byDay[n]!
        default:
            return 0
        }
    }

    // MARK: - OLS slope

    /// Ordinary-least-squares slope of `y` over `x`. Returns 0 for degenerate input.
    private static func olsSlope(_ points: [(dayIndex: Double, kg: Double)]) -> Double {
        let n = Double(points.count)
        guard n >= 2 else { return 0 }
        let meanX = points.map(\.dayIndex).reduce(0, +) / n
        let meanY = points.map(\.kg).reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for p in points {
            let dx = p.dayIndex - meanX
            num += dx * (p.kg - meanY)
            den += dx * dx
        }
        guard den > 0 else { return 0 }
        return num / den
    }
}
