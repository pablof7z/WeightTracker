import Foundation

public struct DatedValue: Identifiable, Equatable, Sendable {
    public let date: Date
    public let value: Double

    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Canonical, unit-stable input shared by every active-cut chart.
///
/// Weight values are always pounds here. Views may convert the fully
/// transformed output to kilograms, but no view recalculates observations,
/// trends, pace, forecasts, or domains.
public struct CutChartModel: Sendable {
    public let startDate: Date
    public let targetDate: Date

    public let startWeightLb: Double
    public let targetWeightLb: Double

    public let raw: [DatedValue]
    public let trailing7: [DatedValue]
    public let requiredPace: [DatedValue]

    public let forecastAnchor: DatedValue
    public let bestForecast: [DatedValue]
    public let typicalForecast: [DatedValue]
    public let worstForecast: [DatedValue]

    public init(
        startDate: Date,
        targetDate: Date,
        startWeightLb: Double,
        targetWeightLb: Double,
        raw: [DatedValue],
        trailing7: [DatedValue],
        requiredPace: [DatedValue],
        forecastAnchor: DatedValue,
        bestForecast: [DatedValue],
        typicalForecast: [DatedValue],
        worstForecast: [DatedValue]
    ) {
        self.startDate = startDate
        self.targetDate = targetDate
        self.startWeightLb = startWeightLb
        self.targetWeightLb = targetWeightLb
        self.raw = raw
        self.trailing7 = trailing7
        self.requiredPace = requiredPace
        self.forecastAnchor = forecastAnchor
        self.bestForecast = bestForecast
        self.typicalForecast = typicalForecast
        self.worstForecast = worstForecast
    }
}

public extension CutChartModel {
    /// Builds the one canonical daily series used by every chart.
    ///
    /// If a day contains multiple values, manually entered readings win. If
    /// more than one preferred reading remains, their mean is used. Otherwise
    /// all readings for that day are averaged. Missing days are never filled.
    static func prepare(
        active: ActiveCut,
        readings: [Reading],
        projection: CutProjectionResult,
        calendar: Calendar = .current
    ) -> CutChartModel {
        let start = calendar.startOfDay(for: active.startDate)
        let target = calendar.startOfDay(for: active.targetEndDate)
        let canonical = canonicalDailyReadings(
            readings.filter { calendar.startOfDay(for: $0.date) >= start },
            calendar: calendar
        )
        let raw = canonical.map {
            DatedValue(date: $0.date, value: UnitConvert.kgToLb($0.weightKg))
        }

        let trailing = raw.map { point -> DatedValue in
            let windowStart = calendar.date(byAdding: .day, value: -6, to: point.date) ?? point.date
            let values = raw
                .filter { $0.date >= windowStart && $0.date <= point.date }
                .map(\.value)
            return DatedValue(date: point.date, value: values.reduce(0, +) / Double(values.count))
        }

        let required = dailyDates(from: start, through: target, calendar: calendar).map { date in
            DatedValue(
                date: date,
                value: requiredPace(
                    at: date,
                    startDate: start,
                    targetDate: target,
                    startWeight: UnitConvert.kgToLb(active.startWeightKg),
                    targetWeight: UnitConvert.kgToLb(active.targetWeightKg)
                )
            )
        }

        let anchor = DatedValue(
            date: calendar.startOfDay(for: projection.anchorDate),
            value: UnitConvert.kgToLb(projection.anchorKg)
        )
        let forecastTargetDate = calendar.startOfDay(for: projection.targetEndDate)

        let best: [DatedValue]
        if let end = projection.bestEndKg, forecastTargetDate > anchor.date {
            best = [anchor, DatedValue(date: forecastTargetDate, value: UnitConvert.kgToLb(end))]
        } else {
            best = [anchor]
        }

        let worst: [DatedValue]
        if let end = projection.worstEndKg, forecastTargetDate > anchor.date {
            worst = [anchor, DatedValue(date: forecastTargetDate, value: UnitConvert.kgToLb(end))]
        } else {
            worst = [anchor]
        }

        // CutProjectionResult already expresses a future path from the
        // present. Keep it unshifted and force the exact shared anchor as the
        // first point so all three forecasts start at one coordinate.
        let futureTypical = projection.avgPath
            .map { DatedValue(date: calendar.startOfDay(for: $0.0), value: UnitConvert.kgToLb($0.1)) }
            .filter { $0.date > anchor.date }
        let typical = [anchor] + futureTypical

        return CutChartModel(
            startDate: start,
            targetDate: target,
            startWeightLb: UnitConvert.kgToLb(active.startWeightKg),
            targetWeightLb: UnitConvert.kgToLb(active.targetWeightKg),
            raw: raw,
            trailing7: trailing,
            requiredPace: required,
            forecastAnchor: anchor,
            bestForecast: best,
            typicalForecast: typical,
            worstForecast: worst
        )
    }

    static func requiredPace(
        at date: Date,
        startDate: Date,
        targetDate: Date,
        startWeight: Double,
        targetWeight: Double
    ) -> Double {
        let duration = targetDate.timeIntervalSince(startDate)
        guard duration > 0 else { return targetWeight }
        let progress = min(1, max(0, date.timeIntervalSince(startDate) / duration))
        return startWeight + progress * (targetWeight - startWeight)
    }

    private static func canonicalDailyReadings(
        _ readings: [Reading],
        calendar: Calendar
    ) -> [(date: Date, weightKg: Double)] {
        let groups = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.date) }
        return groups.map { day, values in
            let manual = values.filter { $0.source == .manual }
            let preferred = manual.isEmpty ? values : manual
            let mean = preferred.map(\.weightKg).reduce(0, +) / Double(preferred.count)
            return (date: day, weightKg: mean)
        }
        .sorted { $0.date < $1.date }
    }

    private static func dailyDates(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        guard start <= end else { return [start] }
        var dates: [Date] = []
        var date = start
        while date <= end {
            dates.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        return dates
    }
}

public enum CutChartMetric: String, Sendable {
    case absoluteWeight
    case remainingToGoal
    case cumulativeLoss
    case paceDelta
    case completionPercent
}

public enum CutChartVariation: String, CaseIterable, Identifiable, Sendable {
    case fixedFullCut = "fixedFullCut"
    case remainingToGoal = "remainingToGoal"
    case cumulativeLoss = "cumulativeLoss"
    case paceDelta = "paceDelta"
    case completionPercent = "completionPercent"
    case recentFocus = "recentFocus"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fixedFullCut: return "Full cut weight"
        case .remainingToGoal: return "Pounds remaining"
        case .cumulativeLoss: return "Cumulative loss"
        case .paceDelta: return "Ahead / behind pace"
        case .completionPercent: return "Goal completion"
        case .recentFocus: return "Recent 30 days"
        }
    }

    public var detail: String {
        switch self {
        case .fixedFullCut: return "Absolute weight across the fixed cut timeline"
        case .remainingToGoal: return "Distance remaining until the target"
        case .cumulativeLoss: return "Progress accumulated since the cut began"
        case .paceDelta: return "How far ahead of or behind the plan you are"
        case .completionPercent: return "Progress normalized to a percentage"
        case .recentFocus: return "Thirty days of history plus a 14-day forecast"
        }
    }

    public var metric: CutChartMetric {
        switch self {
        case .fixedFullCut, .recentFocus: return .absoluteWeight
        case .remainingToGoal: return .remainingToGoal
        case .cumulativeLoss: return .cumulativeLoss
        case .paceDelta: return .paceDelta
        case .completionPercent: return .completionPercent
        }
    }
}

public enum CutChartVariationOrder {
    public static let `default`: [CutChartVariation] = [
        .recentFocus,
        .paceDelta,
        .fixedFullCut,
        .remainingToGoal,
        .cumulativeLoss,
        .completionPercent,
    ]

    public static func decode(_ rawValue: String) -> [CutChartVariation] {
        let decoded = rawValue
            .split(separator: ",")
            .compactMap { CutChartVariation(rawValue: String($0)) }
        return normalized(decoded)
    }

    public static func encode(_ variations: [CutChartVariation]) -> String {
        normalized(variations).map(\.rawValue).joined(separator: ",")
    }

    public static func normalized(_ variations: [CutChartVariation]) -> [CutChartVariation] {
        var seen: Set<CutChartVariation> = []
        let unique = variations.filter { seen.insert($0).inserted }
        return unique + Self.default.filter { !seen.contains($0) }
    }
}

public struct CutChartDomainState: Codable, Equatable, Sendable {
    public var absoluteLower: Double
    public var absoluteUpper: Double
    public var paceHalfRange: Double
    public var recentCenter: Double
    public var recentSpan: Double

    public init(
        absoluteLower: Double,
        absoluteUpper: Double,
        paceHalfRange: Double,
        recentCenter: Double,
        recentSpan: Double = 12
    ) {
        self.absoluteLower = absoluteLower
        self.absoluteUpper = absoluteUpper
        self.paceHalfRange = paceHalfRange
        self.recentCenter = recentCenter
        self.recentSpan = recentSpan
    }

    /// Produces a stable state from immutable cut configuration, optionally
    /// expanding a previously persisted state. Boundaries never contract.
    public static func resolved(
        for model: CutChartModel,
        previous: CutChartDomainState? = nil,
        calendar: Calendar = .current
    ) -> CutChartDomainState {
        let floorCap = max(
            model.targetWeightLb - UnitConvert.kgToLb(0.9),
            model.startWeightLb * 0.85
        )
        let baseLower = floorCap - 1.5
        let baseUpper = model.startWeightLb + 1.5
        let basePaceRange = roundUpToHalf(max(3, (model.startWeightLb - model.targetWeightLb) * 0.20))

        let recentDomain = recentXDomain(model: model, calendar: calendar)
        let recentValues = (model.trailing7 + model.typicalForecast)
            .filter { recentDomain.contains($0.date) }
            .map(\.value)
        let initialRecentCenter: Double = {
            guard let low = recentValues.min(), let high = recentValues.max() else {
                return model.forecastAnchor.value
            }
            return (low + high) / 2
        }()

        var state = previous ?? CutChartDomainState(
            absoluteLower: baseLower,
            absoluteUpper: baseUpper,
            paceHalfRange: basePaceRange,
            recentCenter: initialRecentCenter
        )

        state.absoluteLower = min(state.absoluteLower, baseLower)
        state.absoluteUpper = max(state.absoluteUpper, baseUpper)
        state.paceHalfRange = max(state.paceHalfRange, basePaceRange)
        state.recentSpan = max(0.5, state.recentSpan)

        let weightValues = model.raw.map(\.value)
            + model.trailing7.map(\.value)
            + model.bestForecast.map(\.value)
            + model.typicalForecast.map(\.value)
            + model.worstForecast.map(\.value)
        if let low = weightValues.min(), low < state.absoluteLower {
            state.absoluteLower = low - 1.5
        }
        if let high = weightValues.max(), high > state.absoluteUpper {
            state.absoluteUpper = high + 1.5
        }

        let paceValues = (model.trailing7 + model.bestForecast + model.typicalForecast + model.worstForecast).map {
            model.requiredPaceValue(at: $0.date) - $0.value
        }
        if let outside = paceValues.map({ abs($0) }).max(), outside > state.paceHalfRange {
            state.paceHalfRange = roundUpToHalf(outside)
        }

        if let latestTrend = model.trailing7.last?.value {
            let half = state.recentSpan / 2
            let edgeBuffer = state.recentSpan * 0.20
            let lowerTrigger = state.recentCenter - half + edgeBuffer
            let upperTrigger = state.recentCenter + half - edgeBuffer
            if latestTrend < lowerTrigger {
                state.recentCenter -= ceil(lowerTrigger - latestTrend)
            } else if latestTrend > upperTrigger {
                state.recentCenter += ceil(latestTrend - upperTrigger)
            }
        }

        return state
    }

    private static func roundUpToHalf(_ value: Double) -> Double {
        ceil(value * 2) / 2
    }

    private static func recentXDomain(model: CutChartModel, calendar: Calendar) -> ClosedRange<Date> {
        let latest = model.raw.last?.date ?? model.forecastAnchor.date
        let lower = calendar.date(byAdding: .day, value: -30, to: latest) ?? latest
        let upper = calendar.date(byAdding: .day, value: 14, to: latest) ?? latest
        return lower...upper
    }
}

public enum CutChartDomainStore {
    private static let prefix = "cutChart.domain.v1."

    public static func resolve(
        model: CutChartModel,
        active: ActiveCut,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> CutChartDomainState {
        let key = prefix + cutIdentifier(active, calendar: calendar)
        let previous = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(CutChartDomainState.self, from: $0) }
        let resolved = CutChartDomainState.resolved(for: model, previous: previous, calendar: calendar)
        if resolved != previous, let data = try? JSONEncoder().encode(resolved) {
            defaults.set(data, forKey: key)
        }
        return resolved
    }

    private static func cutIdentifier(_ cut: ActiveCut, calendar: Calendar) -> String {
        let start = Int(calendar.startOfDay(for: cut.startDate).timeIntervalSince1970)
        let end = Int(calendar.startOfDay(for: cut.targetEndDate).timeIntervalSince1970)
        let startWeight = Int((cut.startWeightKg * 1_000).rounded())
        let targetWeight = Int((cut.targetWeightKg * 1_000).rounded())
        return "\(start).\(end).\(startWeight).\(targetWeight)"
    }
}

public struct TransformedCutChartModel: Sendable {
    public let variation: CutChartVariation
    public let raw: [DatedValue]
    public let trend: [DatedValue]
    public let required: [DatedValue]
    public let bestForecast: [DatedValue]
    public let typicalForecast: [DatedValue]
    public let worstForecast: [DatedValue]
    public let forecastAnchor: DatedValue
    public let xDomain: ClosedRange<Date>
    public let yDomain: ClosedRange<Double>
    public let baseline: Double?
    public let targetLine: Double?
}

public enum CutChartTransformer {
    public static func transform(
        _ model: CutChartModel,
        variation: CutChartVariation,
        domains: CutChartDomainState,
        calendar: Calendar = .current
    ) -> TransformedCutChartModel {
        let metric = variation.metric
        let transform: (DatedValue) -> DatedValue = { point in
            DatedValue(date: point.date, value: value(point.value, at: point.date, model: model, metric: metric))
        }

        var raw = model.raw.map(transform)
        var trend = model.trailing7.map(transform)
        var required = model.requiredPace.map(transform)
        var best = model.bestForecast.map(transform)
        var typical = model.typicalForecast.map(transform)
        var worst = model.worstForecast.map(transform)
        let anchor = transform(model.forecastAnchor)

        let xDomain: ClosedRange<Date>
        let yDomain: ClosedRange<Double>
        let baseline: Double?
        let targetLine: Double?

        if variation == .recentFocus {
            let latest = model.raw.last?.date ?? model.forecastAnchor.date
            let lower = calendar.date(byAdding: .day, value: -30, to: latest) ?? latest
            let upper = calendar.date(byAdding: .day, value: 14, to: latest) ?? latest
            xDomain = lower...upper
            let half = domains.recentSpan / 2
            yDomain = (domains.recentCenter - half)...(domains.recentCenter + half)
            raw = raw.filter { xDomain.contains($0.date) }
            trend = trend.filter { xDomain.contains($0.date) }
            required = []
            best = best.filter { xDomain.contains($0.date) }
            typical = typical.filter { xDomain.contains($0.date) }
            worst = worst.filter { xDomain.contains($0.date) }
            baseline = nil
            targetLine = model.targetWeightLb
        } else {
            xDomain = model.startDate...model.targetDate
            switch metric {
            case .absoluteWeight:
                yDomain = domains.absoluteLower...domains.absoluteUpper
                baseline = nil
                targetLine = model.targetWeightLb
            case .remainingToGoal:
                yDomain = (domains.absoluteLower - model.targetWeightLb)...(domains.absoluteUpper - model.targetWeightLb)
                baseline = nil
                targetLine = 0
            case .cumulativeLoss:
                yDomain = min(-2, model.startWeightLb - domains.absoluteUpper)...(model.startWeightLb - domains.absoluteLower)
                baseline = nil
                targetLine = model.startWeightLb - model.targetWeightLb
            case .paceDelta:
                yDomain = (-domains.paceHalfRange)...domains.paceHalfRange
                baseline = 0
                targetLine = nil
            case .completionPercent:
                let goalLoss = model.startWeightLb - model.targetWeightLb
                let floorCap = max(model.targetWeightLb - UnitConvert.kgToLb(0.9), model.startWeightLb * 0.85)
                let floorCompletion = goalLoss == 0 ? 100 : 100 * (model.startWeightLb - floorCap) / goalLoss
                let baseUpper = ceil((floorCompletion + 5) / 5) * 5
                let expandedLower = value(domains.absoluteUpper, at: model.startDate, model: model, metric: metric)
                let expandedUpper = value(domains.absoluteLower, at: model.startDate, model: model, metric: metric)
                yDomain = min(-10, expandedLower)...max(baseUpper, expandedUpper)
                baseline = 0
                targetLine = 100
            }
        }

        return TransformedCutChartModel(
            variation: variation,
            raw: raw,
            trend: trend,
            required: required,
            bestForecast: best,
            typicalForecast: typical,
            worstForecast: worst,
            forecastAnchor: anchor,
            xDomain: xDomain,
            yDomain: yDomain,
            baseline: baseline,
            targetLine: targetLine
        )
    }

    private static func value(
        _ weight: Double,
        at date: Date,
        model: CutChartModel,
        metric: CutChartMetric
    ) -> Double {
        switch metric {
        case .absoluteWeight:
            return weight
        case .remainingToGoal:
            return weight - model.targetWeightLb
        case .cumulativeLoss:
            return model.startWeightLb - weight
        case .paceDelta:
            return model.requiredPaceValue(at: date) - weight
        case .completionPercent:
            let goalLoss = model.startWeightLb - model.targetWeightLb
            guard goalLoss != 0 else { return 0 }
            return 100 * (model.startWeightLb - weight) / goalLoss
        }
    }
}

public extension CutChartModel {
    func requiredPaceValue(at date: Date) -> Double {
        Self.requiredPace(
            at: date,
            startDate: startDate,
            targetDate: targetDate,
            startWeight: startWeightLb,
            targetWeight: targetWeightLb
        )
    }
}
