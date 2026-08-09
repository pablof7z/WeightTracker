import Foundation

/// The Today chart collection. Progress and Recent Trend provide the canonical
/// decision views; the restored lenses expose focused transforms and weekly
/// diagnostics the user explicitly wants available in the carousel.
public enum TodayLens: String, CaseIterable, Identifiable, Sendable {
    case progress
    case currentWeight
    case totalLost
    case thisWeek
    case weeklyAverage
    case recentTrend
    case pace
    case forecast
    case fullCut
    case weeklyRange
    case weeklyLoss

    public var id: String { rawValue }

    /// The lens shown on every cold launch. The current lens is retained for
    /// the session but never persisted across launches, so a deeply secondary
    /// lens can't become the default opening experience.
    public static let launchDefault: TodayLens = .progress

    /// Small factual label rendered above the hero number.
    public var label: String {
        switch self {
        case .progress: return "Progress vs Plan"
        case .currentWeight: return "Current Weight"
        case .totalLost: return "Total Lost"
        case .thisWeek: return "This Week"
        case .weeklyAverage: return "Week-to-Date Average"
        case .recentTrend: return "Recent Trend"
        case .pace: return "Pace History"
        case .forecast: return "Forecast"
        case .fullCut: return "Full Cut"
        case .weeklyRange: return "Weekly Range"
        case .weeklyLoss: return "Week-over-Week Change"
        }
    }

    /// One-line explanation used by Settings so the list is self-describing.
    public var detail: String {
        switch self {
        case .progress: return "Raw readings, current trend, plan, target, and fitted forecast"
        case .currentWeight: return "Recent raw weights with the seven-calendar-day trend"
        case .totalLost: return "Cumulative loss from the configured start weight"
        case .thisWeek: return "Observed change from the last reading before Monday"
        case .weeklyAverage: return "Monday-based weekly means with the current week to date"
        case .recentTrend: return "Fourteen-day fitted pace compared with what is needed now"
        case .pace: return "Historical rolling fourteen-day fitted loss rate"
        case .forecast: return "Target-date estimate from the current fitted trend"
        case .fullCut: return "Raw observations and trend across the entire active cut"
        case .weeklyRange: return "Weekly mean with observed minimum and maximum"
        case .weeklyLoss: return "Change in comparable weekly means"
        }
    }

    /// Spoken lens name for the VoiceOver summary.
    public var accessibilityName: String { label }
}

// MARK: - Canonical Today analytics

public struct RecentPaceFit: Equatable, Sendable {
    /// Conventional signed weight slope. Negative means weight is falling.
    public let slopeLbPerDay: Double
    public let observationCount: Int
    public let windowStart: Date
    public let windowEnd: Date
    public let fittedLine: [DatedValue]
    public let slopeStandardErrorLbPerDay: Double
    public let residualStandardDeviationLb: Double

    public var signedLbPerWeek: Double { slopeLbPerDay * 7 }
    public var lossMagnitudeLbPerWeek: Double { -signedLbPerWeek }
}

public enum NeededPace: Equatable, Sendable {
    /// Positive magnitude in pounds/week for a loss target.
    case available(Double)
    case goalReached
    case deadlinePassed
    case insufficientData
}

public struct TodayTrendForecast: Equatable, Sendable {
    public let anchor: DatedValue
    public let targetDate: Date
    public let projectedTargetWeightLb: Double
    public let lowerTargetWeightLb: Double
    public let upperTargetWeightLb: Double
    public let centerLine: [DatedValue]
    public let lowerLine: [DatedValue]
    public let upperLine: [DatedValue]
}

/// One source of truth for every number and line on Today. It deliberately does
/// not consume the historical-cut/bootstrap or physiology forecast engines:
/// the displayed forecast follows from the same recent fit the user can inspect.
public struct TodayAnalyticsModel: Equatable, Sendable {
    public static let trendWindowDays = 7
    public static let paceWindowDays = 14

    public let asOfDate: Date
    public let startDate: Date
    public let targetDate: Date
    public let startWeightLb: Double
    public let targetWeightLb: Double
    public let observations: [DatedValue]
    public let trend: [DatedValue]
    public let trendObservationCounts: [Int]
    public let plannedTrajectory: [DatedValue]
    public let latestObservation: DatedValue?
    public let currentTrend: DatedValue?
    public let currentTrendObservationCount: Int
    public let plannedWeightAsOfLb: Double
    /// Current trend minus planned weight. Positive means above the loss plan.
    public let trendMinusPlanLb: Double?
    public let originalPlannedLossLbPerWeek: Double
    public let neededNow: NeededPace
    public let recentPace: RecentPaceFit?
    public let forecast: TodayTrendForecast?

    public static func prepare(
        active: ActiveCut,
        readings: [Reading],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayAnalyticsModel {
        let start = calendar.startOfDay(for: active.startDate)
        let target = calendar.startOfDay(for: active.targetEndDate)
        let asOfDay = calendar.startOfDay(for: asOf)
        let canonical = CanonicalDailyWeightSeries.prepare(
            readings: readings,
            from: start,
            through: asOfDay,
            calendar: calendar
        )
        let observations = canonical.map {
            DatedValue(date: $0.date, value: UnitConvert.kgToLb($0.weightKg))
        }

        var trend: [DatedValue] = []
        var trendCounts: [Int] = []
        for point in observations {
            let lower = calendar.date(byAdding: .day, value: -(trendWindowDays - 1), to: point.date) ?? point.date
            let window = observations.filter { $0.date >= lower && $0.date <= point.date }
            let mean = window.map(\.value).reduce(0, +) / Double(window.count)
            trend.append(DatedValue(date: point.date, value: mean))
            trendCounts.append(window.count)
        }

        let startLb = UnitConvert.kgToLb(active.startWeightKg)
        let targetLb = UnitConvert.kgToLb(active.targetWeightKg)
        let plannedTrajectory = [
            DatedValue(date: start, value: startLb),
            DatedValue(date: target, value: targetLb),
        ]
        let plannedWeight = CutChartModel.requiredPace(
            at: min(max(asOfDay, start), target),
            startDate: start,
            targetDate: target,
            startWeight: startLb,
            targetWeight: targetLb,
            calendar: calendar
        )
        let totalDays = max(1, calendar.dateComponents([.day], from: start, to: target).day ?? 1)
        let originalPlanned = (startLb - targetLb) / (Double(totalDays) / 7)
        let currentTrend = trend.last
        let currentCount = trendCounts.last ?? 0

        let neededNow: NeededPace = {
            guard let currentTrend else { return .insufficientData }
            if currentTrend.value <= targetLb { return .goalReached }
            let remaining = calendar.dateComponents([.day], from: asOfDay, to: target).day ?? 0
            guard remaining > 0 else { return .deadlinePassed }
            return .available(max(0, (currentTrend.value - targetLb) / (Double(remaining) / 7)))
        }()

        let recent = recentPaceFit(observations: observations, calendar: calendar)
        let forecast = makeForecast(
            currentTrend: currentTrend,
            recentPace: recent,
            asOf: asOfDay,
            targetDate: target,
            calendar: calendar
        )

        return TodayAnalyticsModel(
            asOfDate: asOfDay,
            startDate: start,
            targetDate: target,
            startWeightLb: startLb,
            targetWeightLb: targetLb,
            observations: observations,
            trend: trend,
            trendObservationCounts: trendCounts,
            plannedTrajectory: plannedTrajectory,
            latestObservation: observations.last,
            currentTrend: currentTrend,
            currentTrendObservationCount: currentCount,
            plannedWeightAsOfLb: plannedWeight,
            trendMinusPlanLb: currentTrend.map { $0.value - plannedWeight },
            originalPlannedLossLbPerWeek: originalPlanned,
            neededNow: neededNow,
            recentPace: recent,
            forecast: forecast
        )
    }

    static func recentPaceFit(
        observations: [DatedValue],
        calendar: Calendar
    ) -> RecentPaceFit? {
        guard let latest = observations.last else { return nil }
        let lower = calendar.date(byAdding: .day, value: -(paceWindowDays - 1), to: latest.date) ?? latest.date
        let points = observations.filter { $0.date >= lower && $0.date <= latest.date }
        guard points.count >= 3, let first = points.first else { return nil }
        let span = calendar.dateComponents([.day], from: first.date, to: latest.date).day ?? 0
        guard span >= 7 else { return nil }

        let xs = points.map { Double(calendar.dateComponents([.day], from: first.date, to: $0.date).day ?? 0) }
        let ys = points.map(\.value)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + pow($1 - meanX, 2) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        let residuals = zip(xs, ys).map { $0.1 - (intercept + slope * $0.0) }
        let degrees = max(1, points.count - 2)
        let residualVariance = residuals.reduce(0) { $0 + $1 * $1 } / Double(degrees)
        let residualSD = sqrt(max(0, residualVariance))
        let slopeSE = sqrt(max(0, residualVariance / sxx))
        let lastX = xs.last ?? 0

        return RecentPaceFit(
            slopeLbPerDay: slope,
            observationCount: points.count,
            windowStart: first.date,
            windowEnd: latest.date,
            fittedLine: [
                DatedValue(date: first.date, value: intercept),
                DatedValue(date: latest.date, value: intercept + slope * lastX),
            ],
            slopeStandardErrorLbPerDay: slopeSE,
            residualStandardDeviationLb: residualSD
        )
    }

    private static func makeForecast(
        currentTrend: DatedValue?,
        recentPace: RecentPaceFit?,
        asOf: Date,
        targetDate: Date,
        calendar: Calendar
    ) -> TodayTrendForecast? {
        guard let currentTrend, let recentPace else { return nil }
        let days = calendar.dateComponents([.day], from: asOf, to: targetDate).day ?? 0
        guard days > 0 else { return nil }
        let horizon = Double(days)
        let projected = currentTrend.value + recentPace.slopeLbPerDay * horizon
        let levelSE = recentPace.residualStandardDeviationLb / sqrt(Double(recentPace.observationCount))
        let slopeSEAtTarget = recentPace.slopeStandardErrorLbPerDay * horizon
        let halfWidth = 1.96 * sqrt(levelSE * levelSE + slopeSEAtTarget * slopeSEAtTarget)
        guard halfWidth.isFinite, halfWidth <= 8 else { return nil }
        let anchor = DatedValue(date: asOf, value: currentTrend.value)
        let end = DatedValue(date: targetDate, value: projected)
        let lowerEnd = DatedValue(date: targetDate, value: projected - halfWidth)
        let upperEnd = DatedValue(date: targetDate, value: projected + halfWidth)
        return TodayTrendForecast(
            anchor: anchor,
            targetDate: targetDate,
            projectedTargetWeightLb: projected,
            lowerTargetWeightLb: lowerEnd.value,
            upperTargetWeightLb: upperEnd.value,
            centerLine: [anchor, end],
            lowerLine: [anchor, lowerEnd],
            upperLine: [anchor, upperEnd]
        )
    }
}

// MARK: - Carousel order + visibility

/// The persisted Today carousel arrangement. `TodayLens` is the canonical list
/// of available visualizations; this type is the only thing that turns a stored
/// string into a usable ordering. Unknown raw values are silently dropped and
/// missing cases are backfilled from the default order, so a stale persisted
/// string can never yield an empty or ill-typed carousel.
public enum TodayLensOrder {
    public static let `default`: [TodayLens] = [
        .progress,
        .currentWeight,
        .totalLost,
        .thisWeek,
        .weeklyAverage,
        .recentTrend,
        .pace,
        .forecast,
        .fullCut,
        .weeklyRange,
        .weeklyLoss,
    ]

    public static func decode(_ rawValue: String) -> [TodayLens] {
        normalized(rawValue.split(separator: ",").compactMap { token in
            let value = String(token)
            // The reduced three-view release called the weekly mean/range page
            // `weeklySummary`; retain the user's saved position during restore.
            if value == "weeklySummary" { return .weeklyAverage }
            return TodayLens(rawValue: value)
        })
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
        Set(rawValue.split(separator: ",").compactMap { token in
            let value = String(token)
            if value == "weeklySummary" { return .weeklyAverage }
            return TodayLens(rawValue: value)
        })
    }

    /// Encoded in canonical order so the stored string is stable regardless of
    /// set iteration order.
    public static func encodeHidden(_ hidden: Set<TodayLens>) -> String {
        Self.default.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
    }

    /// The lenses the carousel should actually render, in the saved order.
    /// Never empty: hiding everything falls back to Progress rather than
    /// producing an empty pager.
    public static func enabled(orderRaw: String, hiddenRaw: String) -> [TodayLens] {
        let hidden = decodeHidden(hiddenRaw)
        let visible = decode(orderRaw).filter { !hidden.contains($0) }
        return visible.isEmpty ? [TodayLens.launchDefault] : visible
    }

    /// The lens a cold launch opens on: Progress when it is enabled,
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
