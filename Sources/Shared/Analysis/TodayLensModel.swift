import Foundation

/// The curated set of Today "lenses" — each a single mathematical perspective
/// on the active cut. Order is deliberate and fixed; the carousel is curated,
/// not exhaustive. Every lens consumes the one canonical daily pipeline
/// (`CanonicalDailyWeightSeries` / `CutChartModel`) so no view recomputes
/// observations, trends, pace, forecasts, or domains.
///
/// Overlapping transforms from the previous carousel (pounds-remaining, goal
/// completion percent, ahead/behind pace as its own page, weekly-loss bars)
/// are intentionally *not* separate lenses — they are affine restatements of
/// Current Weight / Total Lost, supporting figures inside Pace, or content for
/// the deeper weekly detail screen.
public enum TodayLens: String, CaseIterable, Identifiable, Sendable {
    case currentWeight
    case totalLost
    case thisWeek
    case weeklyAverage
    case pace
    case forecast
    case fullCut
    case weeklyRange
    case weeklyLoss

    public var id: String { rawValue }

    /// The lens shown on every cold launch. The current lens is retained for
    /// the session but never persisted across launches, so a deeply secondary
    /// lens can't become the default opening experience.
    public static let launchDefault: TodayLens = .currentWeight

    /// Small factual label rendered above the hero number.
    public var label: String {
        switch self {
        case .currentWeight: return "Current weight"
        case .totalLost: return "Total lost"
        case .thisWeek: return "This week"
        case .weeklyAverage: return "Weekly average"
        case .pace: return "Pace"
        case .forecast: return "Forecast"
        case .fullCut: return "Full cut"
        case .weeklyRange: return "Weekly range"
        case .weeklyLoss: return "Weekly loss"
        }
    }

    /// One-line explanation used by Settings so the list is self-describing.
    public var detail: String {
        switch self {
        case .currentWeight: return "Latest weight over the last 30 days with its trailing trend"
        case .totalLost: return "Cumulative pounds lost since the cut began, against the goal"
        case .thisWeek: return "Signed change so far this calendar week"
        case .weeklyAverage: return "Weekly mean weight and the change versus the prior week"
        case .pace: return "Rolling loss rate per week against the rate still required"
        case .forecast: return "Projected weight on the target date with its uncertainty band"
        case .fullCut: return "Absolute weight across the entire cut, start to target date"
        case .weeklyRange: return "Weekly average with the observed minimum and maximum each week"
        case .weeklyLoss: return "Week-over-week change as bars against the required weekly rate"
        }
    }

    /// Spoken lens name for the VoiceOver summary.
    public var accessibilityName: String { label }
}

// MARK: - Carousel order + visibility

/// The persisted Today carousel arrangement. `TodayLens` is the canonical list
/// of available visualizations; this type is the only thing that turns a stored
/// string into a usable ordering. Unknown raw values are silently dropped and
/// missing cases are backfilled from the default order, so a stale persisted
/// string can never yield an empty or ill-typed carousel.
public enum TodayLensOrder {
    public static let `default`: [TodayLens] = TodayLens.allCases

    public static func decode(_ rawValue: String) -> [TodayLens] {
        normalized(
            rawValue
                .split(separator: ",")
                .compactMap { TodayLens(rawValue: String($0)) }
        )
    }

    public static func encode(_ lenses: [TodayLens]) -> String {
        normalized(lenses).map(\.rawValue).joined(separator: ",")
    }

    public static func normalized(_ lenses: [TodayLens]) -> [TodayLens] {
        var seen: Set<TodayLens> = []
        let unique = lenses.filter { seen.insert($0).inserted }
        return unique + Self.default.filter { !seen.contains($0) }
    }

    // MARK: Hidden set

    public static func decodeHidden(_ rawValue: String) -> Set<TodayLens> {
        Set(rawValue.split(separator: ",").compactMap { TodayLens(rawValue: String($0)) })
    }

    /// Encoded in canonical order so the stored string is stable regardless of
    /// set iteration order.
    public static func encodeHidden(_ hidden: Set<TodayLens>) -> String {
        Self.default.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
    }

    /// The lenses the carousel should actually render, in the saved order.
    /// Never empty: hiding everything falls back to Current Weight rather than
    /// producing an empty pager.
    public static func enabled(orderRaw: String, hiddenRaw: String) -> [TodayLens] {
        let hidden = decodeHidden(hiddenRaw)
        let visible = decode(orderRaw).filter { !hidden.contains($0) }
        return visible.isEmpty ? [TodayLens.launchDefault] : visible
    }

    /// The lens a cold launch opens on: Current Weight when it is enabled,
    /// otherwise the first enabled lens.
    public static func launchLens(in enabled: [TodayLens]) -> TodayLens {
        if enabled.contains(TodayLens.launchDefault) { return .launchDefault }
        return enabled.first ?? .launchDefault
    }
}

// MARK: - Pace lens

/// Rate lens data. The series is a genuine rate in pounds/week derived from a
/// trailing, date-aware least-squares regression — never a differentiated
/// daily reading and never a weight curve overlaid on a rate axis. Loss pace
/// is expressed as a positive magnitude for display even though the internal
/// slope is negative while losing.
public struct PaceLensModel: Equatable, Sendable {
    /// Rolling actual loss pace over time, in lb/week. Positive means losing.
    public let actual: [DatedValue]
    /// The plan's constant required rate: (start − target) / total weeks.
    public let requiredConstant: Double
    /// Required rate *now* to still hit the target by the configured end date,
    /// computed from the current anchor. Zero once the target is reached.
    public let requiredNow: Double
    /// Latest observed pace magnitude (lb/week), or nil with too little data.
    public let latest: Double?
    /// latest − requiredNow. Positive means faster than currently required.
    public let vsRequired: Double?
    /// Typical projected weight on the target date (lb), or nil if unavailable.
    public let projectedTargetWeightLb: Double?
    public let xDomain: ClosedRange<Date>
    public let yDomain: ClosedRange<Double>
    public let windowDays: Int

    public init(
        actual: [DatedValue],
        requiredConstant: Double,
        requiredNow: Double,
        latest: Double?,
        vsRequired: Double?,
        projectedTargetWeightLb: Double?,
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>,
        windowDays: Int
    ) {
        self.actual = actual
        self.requiredConstant = requiredConstant
        self.requiredNow = requiredNow
        self.latest = latest
        self.vsRequired = vsRequired
        self.projectedTargetWeightLb = projectedTargetWeightLb
        self.xDomain = xDomain
        self.yDomain = yDomain
        self.windowDays = windowDays
    }

    public static func prepare(
        active: ActiveCut,
        readings: [Reading],
        projection: CutProjectionResult,
        asOf: Date = Date(),
        calendar: Calendar = .current,
        windowDays: Int = 14,
        historyDays: Int = 30
    ) -> PaceLensModel {
        let start = calendar.startOfDay(for: active.startDate)
        let end = calendar.startOfDay(for: active.targetEndDate)
        let today = calendar.startOfDay(for: asOf)
        let canonical = CanonicalDailyWeightSeries.prepare(
            readings: readings,
            from: start,
            through: today,
            calendar: calendar
        ).map { DatedValue(date: $0.date, value: UnitConvert.kgToLb($0.weightKg)) }

        let startLb = UnitConvert.kgToLb(active.startWeightKg)
        let targetLb = UnitConvert.kgToLb(active.targetWeightKg)

        // Plan-constant required rate.
        let totalDays = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        let requiredConstant = (startLb - targetLb) / (Double(totalDays) / 7.0)

        // Required rate from the current anchor to still hit target by the end.
        let anchorLb = UnitConvert.kgToLb(projection.anchorKg)
        let daysRemaining = max(0, calendar.dateComponents([.day], from: today, to: end).day ?? 0)
        let requiredNow: Double = {
            guard daysRemaining > 0, !projection.isTargetReached else { return 0 }
            return max(0, (anchorLb - targetLb) / (Double(daysRemaining) / 7.0))
        }()

        // Rolling trailing regression → lb/week (positive = losing).
        var actual: [DatedValue] = []
        for point in canonical {
            let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: point.date) ?? point.date
            let window = canonical.filter { $0.date >= windowStart && $0.date <= point.date }
            guard window.count >= 3,
                  let first = window.first?.date,
                  let last = window.last?.date,
                  (calendar.dateComponents([.day], from: first, to: last).day ?? 0) >= 3
            else { continue }
            guard let slopePerDay = leastSquaresSlopePerDay(window, calendar: calendar) else { continue }
            // slope is lb/day of weight change; loss pace = negative slope, ×7.
            actual.append(DatedValue(date: point.date, value: -slopePerDay * 7.0))
        }

        let latest = actual.last?.value
        let vsRequired = latest.map { $0 - requiredNow }

        let projectedTargetWeightLb = projection.avgPath.last.map { UnitConvert.kgToLb($0.1) }

        let lower = calendar.date(byAdding: .day, value: -historyDays, to: today) ?? today
        let xDomain = lower...today
        let visible = actual.filter { xDomain.contains($0.date) }.map(\.value)
        let yDomain = paceYDomain(
            values: visible + [requiredConstant, requiredNow]
        )

        return PaceLensModel(
            actual: actual,
            requiredConstant: requiredConstant,
            requiredNow: requiredNow,
            latest: latest,
            vsRequired: vsRequired,
            projectedTargetWeightLb: projectedTargetWeightLb,
            xDomain: xDomain,
            yDomain: yDomain,
            windowDays: windowDays
        )
    }

    /// Ordinary least-squares slope of weight (lb) over time (days). Returns nil
    /// for a degenerate window with zero time span.
    static func leastSquaresSlopePerDay(_ points: [DatedValue], calendar: Calendar) -> Double? {
        guard let origin = points.first?.date, points.count >= 2 else { return nil }
        let xs = points.map { Double(calendar.dateComponents([.day], from: origin, to: $0.date).day ?? 0) }
        let ys = points.map(\.value)
        let n = Double(points.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXX = zip(xs, xs).map(*).reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 1e-9 else { return nil }
        return (n * sumXY - sumX * sumY) / denom
    }

    private static func paceYDomain(values: [Double]) -> ClosedRange<Double> {
        let minV = min(0, values.min() ?? 0)
        let maxV = max(values.max() ?? 1, 0)
        // Keep zero visible, a floor span so a steady rate doesn't look dramatic.
        var lower = floor((minV - 0.3) * 2) / 2
        var upper = ceil((maxV + 0.5) * 2) / 2
        if upper - lower < 3 { upper = lower + 3 }
        if lower > 0 { lower = 0 }
        if upper < 0 { upper = 0 }
        return lower...upper
    }
}

// MARK: - This Week lens

/// Signed cumulative weight change during the current calendar week (Monday
/// through Sunday). The baseline is the last canonical reading strictly before
/// the week began; if none exists the first reading in the week is used and the
/// period is marked partial. Missing days are never interpolated, so points
/// exist only where a reading exists, and the final point equals the headline.
public struct ThisWeekModel: Equatable, Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    /// Baseline weight (lb) that each point is measured against, or nil when the
    /// week contains no readings at all.
    public let baselineLb: Double?
    /// True when there was no reading before the week, so the baseline is the
    /// first in-week reading and the comparison is only partial.
    public let isPartial: Bool
    /// date → (readingLb − baselineLb), only for observed days. The line ends at
    /// the headline value.
    public let points: [DatedValue]
    /// Signed change so far this week (negative means lost). Nil with no data.
    public let headline: Double?
    /// Average signed change per elapsed day since the week began.
    public let avgPerDay: Double?
    /// Mean of the raw readings logged this week (lb).
    public let weekAverageLb: Double?
    public let daysLogged: Int
    /// Elapsed calendar days in the week up to `asOf` (the "of 7" denominator).
    public let daysElapsed: Int
    public let xDomain: ClosedRange<Date>
    public let yDomain: ClosedRange<Double>

    public init(
        weekStart: Date,
        weekEnd: Date,
        baselineLb: Double?,
        isPartial: Bool,
        points: [DatedValue],
        headline: Double?,
        avgPerDay: Double?,
        weekAverageLb: Double?,
        daysLogged: Int,
        daysElapsed: Int,
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.baselineLb = baselineLb
        self.isPartial = isPartial
        self.points = points
        self.headline = headline
        self.avgPerDay = avgPerDay
        self.weekAverageLb = weekAverageLb
        self.daysLogged = daysLogged
        self.daysElapsed = daysElapsed
        self.xDomain = xDomain
        self.yDomain = yDomain
    }

    public static func prepare(
        active: ActiveCut,
        readings: [Reading],
        asOf: Date = Date(),
        calendar baseCalendar: Calendar = .current,
        baseHalfSpan: Double = 4
    ) -> ThisWeekModel {
        var calendar = baseCalendar
        calendar.firstWeekday = 2 // Monday
        calendar.minimumDaysInFirstWeek = 4

        let today = calendar.startOfDay(for: asOf)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start
            ?? calendar.startOfDay(for: today)
        let weekEndFull = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        // Canonical daily series across the whole cut so the pre-week baseline
        // is available. Never fills missing days.
        let cutStart = calendar.startOfDay(for: active.startDate)
        let canonical = CanonicalDailyWeightSeries.prepare(
            readings: readings,
            from: cutStart,
            through: today,
            calendar: calendar
        ).map { DatedValue(date: $0.date, value: UnitConvert.kgToLb($0.weightKg)) }

        let inWeek = canonical.filter { $0.date >= weekStart && $0.date <= min(today, weekEndFull) }
        let priorBaseline = canonical.last(where: { $0.date < weekStart })

        let baseline: DatedValue?
        let isPartial: Bool
        if let priorBaseline {
            baseline = priorBaseline
            isPartial = false
        } else if let firstInWeek = inWeek.first {
            baseline = firstInWeek
            isPartial = true
        } else {
            baseline = nil
            isPartial = inWeek.isEmpty
        }

        let baselineLb = baseline?.value
        let points: [DatedValue] = baselineLb.map { base in
            inWeek.map { DatedValue(date: $0.date, value: $0.value - base) }
        } ?? []

        let headline = points.last?.value
        let weekValues = inWeek.map(\.value)
        let weekAverageLb = weekValues.isEmpty ? nil : weekValues.reduce(0, +) / Double(weekValues.count)

        let daysElapsed = max(1, (calendar.dateComponents([.day], from: weekStart, to: min(today, weekEndFull)).day ?? 0) + 1)
        let avgPerDay: Double? = {
            guard let headline, let lastDate = inWeek.last?.date else { return nil }
            let span = max(1, (calendar.dateComponents([.day], from: weekStart, to: lastDate).day ?? 0) + 1)
            return headline / Double(span)
        }()

        // Fixed symmetric range around zero; only expand if genuinely exceeded.
        let magnitude = points.map { abs($0.value) }.max() ?? 0
        let half = max(baseHalfSpan, ceil(magnitude))
        let yDomain = (-half)...half

        return ThisWeekModel(
            weekStart: weekStart,
            weekEnd: weekEndFull,
            baselineLb: baselineLb,
            isPartial: isPartial,
            points: points,
            headline: headline,
            avgPerDay: avgPerDay,
            weekAverageLb: weekAverageLb,
            daysLogged: inWeek.count,
            daysElapsed: daysElapsed,
            xDomain: weekStart...weekEndFull,
            yDomain: yDomain
        )
    }
}
