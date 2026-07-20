import Foundation

/// The four weekly renderings all consume this one aggregation output.
/// Weight values are canonical pounds until `WeeklyCutChartPresentation`
/// converts them for display.
public struct WeeklyCutPoint: Identifiable, Equatable, Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    public let averageWeight: Double
    public let minWeight: Double
    public let maxWeight: Double
    public let readingCount: Int
    public let lossVsPrevious: Double?
    public let plannedAverage: Double
    public let aheadOfPlan: Double
    public let isPartial: Bool
    public let isWeekToDate: Bool

    public var id: Date { weekStart }

    public init(
        weekStart: Date,
        weekEnd: Date,
        averageWeight: Double,
        minWeight: Double,
        maxWeight: Double,
        readingCount: Int,
        lossVsPrevious: Double?,
        plannedAverage: Double,
        aheadOfPlan: Double,
        isPartial: Bool,
        isWeekToDate: Bool
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.averageWeight = averageWeight
        self.minWeight = minWeight
        self.maxWeight = maxWeight
        self.readingCount = readingCount
        self.lossVsPrevious = lossVsPrevious
        self.plannedAverage = plannedAverage
        self.aheadOfPlan = aheadOfPlan
        self.isPartial = isPartial
        self.isWeekToDate = isWeekToDate
    }

    fileprivate func replacing(lossVsPrevious: Double?) -> WeeklyCutPoint {
        WeeklyCutPoint(
            weekStart: weekStart,
            weekEnd: weekEnd,
            averageWeight: averageWeight,
            minWeight: minWeight,
            maxWeight: maxWeight,
            readingCount: readingCount,
            lossVsPrevious: lossVsPrevious,
            plannedAverage: plannedAverage,
            aheadOfPlan: aheadOfPlan,
            isPartial: isPartial,
            isWeekToDate: isWeekToDate
        )
    }
}

public struct WeeklyCutChartDomains: Equatable, Sendable {
    public let averageWeight: ClosedRange<Double>
    public let weeklyLoss: ClosedRange<Double>

    public init(
        averageWeight: ClosedRange<Double>,
        weeklyLoss: ClosedRange<Double>
    ) {
        self.averageWeight = averageWeight
        self.weeklyLoss = weeklyLoss
    }
}

public struct WeeklyCutChartModel: Equatable, Sendable {
    public let points: [WeeklyCutPoint]
    public let requiredWeeklyLoss: Double
    public let domains: WeeklyCutChartDomains

    public init(
        points: [WeeklyCutPoint],
        requiredWeeklyLoss: Double,
        domains: WeeklyCutChartDomains
    ) {
        self.points = points
        self.requiredWeeklyLoss = requiredWeeklyLoss
        self.domains = domains
    }

    public static func prepare(
        active: ActiveCut,
        readings: [Reading],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyCutChartModel {
        let weeklyCalendar = mondayCalendar(from: calendar)
        let cutStart = weeklyCalendar.startOfDay(for: active.startDate)
        let cutEnd = weeklyCalendar.startOfDay(for: active.targetEndDate)
        let today = weeklyCalendar.startOfDay(for: asOf)
        let observationEnd = min(today, cutEnd)
        let daily = CanonicalDailyWeightSeries.prepare(
            readings: readings,
            from: cutStart,
            through: observationEnd,
            calendar: weeklyCalendar
        )
        let grouped = Dictionary(grouping: daily) {
            weekStart(containing: $0.date, calendar: weeklyCalendar)
        }
        let startWeek = weekStart(containing: cutStart, calendar: weeklyCalendar)
        let endWeek = weekStart(containing: cutEnd, calendar: weeklyCalendar)
        let currentWeek = weekStart(containing: today, calendar: weeklyCalendar)
        let startWeight = UnitConvert.kgToLb(active.startWeightKg)
        let targetWeight = UnitConvert.kgToLb(active.targetWeightKg)

        var observationsByWeek: [Date: [CanonicalDailyWeight]] = [:]
        var points = grouped.keys.sorted().compactMap { weekStart -> WeeklyCutPoint? in
            guard let observations = grouped[weekStart], !observations.isEmpty else { return nil }
            observationsByWeek[weekStart] = observations
            let values = observations.map { UnitConvert.kgToLb($0.weightKg) }
            let average = mean(values)
            let plannedValues = observations.map { observation in
                CutChartModel.requiredPace(
                    at: observation.date,
                    startDate: cutStart,
                    targetDate: cutEnd,
                    startWeight: startWeight,
                    targetWeight: targetWeight
                )
            }
            let plannedAverage = mean(plannedValues)
            let calendarWeekEnd = weeklyCalendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let isBoundaryPartial = (weekStart == startWeek && cutStart > weekStart)
                || (weekStart == endWeek && cutEnd < calendarWeekEnd)
            let isWeekToDate = weekStart == currentWeek && today < cutEnd
            let periodEnd = isWeekToDate ? min(today, calendarWeekEnd) : min(cutEnd, calendarWeekEnd)

            return WeeklyCutPoint(
                weekStart: weekStart,
                weekEnd: periodEnd,
                averageWeight: average,
                minWeight: values.min() ?? average,
                maxWeight: values.max() ?? average,
                readingCount: values.count,
                lossVsPrevious: nil,
                plannedAverage: plannedAverage,
                aheadOfPlan: plannedAverage - average,
                isPartial: isBoundaryPartial,
                isWeekToDate: isWeekToDate
            )
        }

        for index in points.indices {
            guard index > points.startIndex else { continue }
            let current = points[index]
            let previous = points[points.index(before: index)]
            guard isConsecutive(previous: previous, current: current, calendar: weeklyCalendar),
                  !current.isPartial,
                  !previous.isPartial
            else { continue }

            let loss: Double?
            if current.isWeekToDate {
                let elapsedDays = max(
                    0,
                    weeklyCalendar.dateComponents(
                        [.day],
                        from: current.weekStart,
                        to: today
                    ).day ?? 0
                )
                let comparisonEnd = weeklyCalendar.date(
                    byAdding: .day,
                    value: min(6, elapsedDays),
                    to: previous.weekStart
                ) ?? previous.weekEnd
                let matchingPrevious = (observationsByWeek[previous.weekStart] ?? [])
                    .filter { $0.date <= comparisonEnd }
                    .map { UnitConvert.kgToLb($0.weightKg) }
                loss = matchingPrevious.isEmpty
                    ? nil
                    : mean(matchingPrevious) - current.averageWeight
            } else if !previous.isWeekToDate {
                loss = previous.averageWeight - current.averageWeight
            } else {
                loss = nil
            }

            points[index] = current.replacing(lossVsPrevious: loss)
        }

        let durationDays = max(
            1,
            weeklyCalendar.dateComponents([.day], from: cutStart, to: cutEnd).day ?? 1
        )
        let durationWeeks = Double(durationDays) / 7.0
        let requiredWeeklyLoss = (startWeight - targetWeight) / durationWeeks
        let domains = resolveDomains(points: points, requiredWeeklyLoss: requiredWeeklyLoss)
        return WeeklyCutChartModel(
            points: points,
            requiredWeeklyLoss: requiredWeeklyLoss,
            domains: domains
        )
    }

    private static func mondayCalendar(from calendar: Calendar) -> Calendar {
        var result = calendar
        result.firstWeekday = 2
        result.minimumDaysInFirstWeek = 4
        return result
    }

    private static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    private static func isConsecutive(
        previous: WeeklyCutPoint,
        current: WeeklyCutPoint,
        calendar: Calendar
    ) -> Bool {
        calendar.date(byAdding: .day, value: 7, to: previous.weekStart) == current.weekStart
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    private static func resolveDomains(
        points: [WeeklyCutPoint],
        requiredWeeklyLoss: Double
    ) -> WeeklyCutChartDomains {
        let weightValues = points.flatMap {
            [$0.minWeight, $0.maxWeight, $0.averageWeight, $0.plannedAverage]
        }
        let weightLow = weightValues.min() ?? 0
        let weightHigh = weightValues.max() ?? 1
        let weightSpan = max(1, weightHigh - weightLow)
        let weightPadding = max(0.75, weightSpan * 0.08)

        let lossValues = points.compactMap(\.lossVsPrevious) + [requiredWeeklyLoss, 0]
        let lossMagnitude = max(0.5, lossValues.map { abs($0) }.max() ?? 0.5)
        let lossPadding = max(0.25, lossMagnitude * 0.15)

        return WeeklyCutChartDomains(
            averageWeight: (weightLow - weightPadding)...(weightHigh + weightPadding),
            weeklyLoss: (-(lossMagnitude + lossPadding))...(lossMagnitude + lossPadding)
        )
    }
}

public enum WeeklyCutChartMode: String, CaseIterable, Identifiable, Sendable {
    case average = "weeklyAverage"
    case averageWithRange = "weeklyAverageWithRange"
    case exactLoss = "exactWeeklyLoss"
    case versusRequiredPace = "weeklyAverageVersusRequiredPace"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .average: return "Weekly average"
        case .averageWithRange: return "Average + range"
        case .exactLoss: return "Exact weekly loss"
        case .versusRequiredPace: return "Average vs plan"
        }
    }

    public var detail: String {
        switch self {
        case .average: return "Weekly mean, reading count, and exact comparable change"
        case .averageWithRange: return "Weekly mean with observed minimum and maximum"
        case .exactLoss: return "Comparable change in weekly averages against the required rate"
        case .versusRequiredPace: return "Observed weekly average against required pace on observed dates"
        }
    }
}

/// A single page in the Today chart carousel. Existing daily projections and
/// weekly aggregations share one selection and one persisted swipe order.
public enum TodayChartPage: Hashable, Identifiable, Sendable {
    case daily(CutChartVariation)
    case weekly(WeeklyCutChartMode)

    public var id: String { rawValue }

    public var rawValue: String {
        switch self {
        case let .daily(variation): return variation.rawValue
        case let .weekly(mode): return mode.rawValue
        }
    }

    public init?(rawValue: String) {
        if let variation = CutChartVariation(rawValue: rawValue) {
            self = .daily(variation)
        } else if let mode = WeeklyCutChartMode(rawValue: rawValue) {
            self = .weekly(mode)
        } else {
            return nil
        }
    }

    public var label: String {
        switch self {
        case let .daily(variation): return variation.label
        case let .weekly(mode): return mode.label
        }
    }

    public var detail: String {
        switch self {
        case let .daily(variation): return variation.detail
        case let .weekly(mode): return mode.detail
        }
    }

    public var dailyVariation: CutChartVariation? {
        guard case let .daily(variation) = self else { return nil }
        return variation
    }

    public var weeklyMode: WeeklyCutChartMode? {
        guard case let .weekly(mode) = self else { return nil }
        return mode
    }
}

public enum TodayChartPageOrder {
    public static let `default`: [TodayChartPage] =
        CutChartVariationOrder.default.map(TodayChartPage.daily)
        + WeeklyCutChartMode.allCases.map(TodayChartPage.weekly)

    public static func decode(_ rawValue: String) -> [TodayChartPage] {
        let decoded = rawValue
            .split(separator: ",")
            .compactMap { TodayChartPage(rawValue: String($0)) }
        return normalized(decoded)
    }

    public static func encode(_ pages: [TodayChartPage]) -> String {
        normalized(pages).map(\.rawValue).joined(separator: ",")
    }

    public static func normalized(_ pages: [TodayChartPage]) -> [TodayChartPage] {
        var seen: Set<TodayChartPage> = []
        let unique = pages.filter { seen.insert($0).inserted }
        return unique + Self.default.filter { !seen.contains($0) }
    }
}

/// Unit conversion, labels, domains, and accessibility copy are prepared once
/// here. SwiftUI chart views only choose marks from this shared output.
public struct WeeklyCutChartPresentation: Equatable, Sendable {
    public struct Point: Identifiable, Equatable, Sendable {
        public let weekStart: Date
        public let weekEnd: Date
        public let averageWeight: Double
        public let minWeight: Double
        public let maxWeight: Double
        public let readingCount: Int
        public let lossVsPrevious: Double?
        public let plannedAverage: Double
        public let aheadOfPlan: Double
        public let isPartial: Bool
        public let isWeekToDate: Bool
        public let weekLabel: String
        public let periodLabel: String
        public let averageText: String
        public let rangeText: String
        public let lossText: String?
        public let lossValueText: String?
        public let compactLossText: String?
        public let aheadText: String
        public let aheadValueText: String

        public var id: Date { weekStart }

        public func accessibilityDescription(for mode: WeeklyCutChartMode) -> String {
            let status = isWeekToDate ? " Week to date." : (isPartial ? " Partial week." : "")
            switch mode {
            case .average:
                return "\(periodLabel). Average \(averageText), \(readingCount) readings. \(lossText ?? "No comparable prior week").\(status)"
            case .averageWithRange:
                return "\(periodLabel). Average \(averageText), range \(rangeText), \(readingCount) readings. \(lossText ?? "No comparable prior week").\(status)"
            case .exactLoss:
                return "\(periodLabel). \(lossText ?? "No comparable weekly loss").\(status)"
            case .versusRequiredPace:
                return "\(periodLabel). Average \(averageText). \(aheadText).\(status)"
            }
        }
    }

    public let points: [Point]
    public let requiredWeeklyLoss: Double
    public let requiredWeeklyLossText: String
    public let compactRequiredWeeklyLossText: String
    public let averageWeightDomain: ClosedRange<Double>
    public let weeklyLossDomain: ClosedRange<Double>
    public let weekDomain: ClosedRange<Date>
    public let unit: WeightUnit

    public init(
        model: WeeklyCutChartModel,
        unit: WeightUnit,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.unit = unit
        let shortDate = DateFormatter()
        shortDate.calendar = calendar
        shortDate.timeZone = calendar.timeZone
        shortDate.locale = locale
        shortDate.setLocalizedDateFormatFromTemplate("MMM d")

        func display(_ pounds: Double) -> Double {
            unit == .lbs ? pounds : UnitConvert.lbToKg(pounds)
        }

        func valueText(_ value: Double, signed: Bool = false) -> String {
            let format = signed ? "%+.2f %@" : "%.2f %@"
            return String(format: format, locale: locale, value, unit.symbol)
        }

        self.points = model.points.map { point in
            let average = display(point.averageWeight)
            let minimum = display(point.minWeight)
            let maximum = display(point.maxWeight)
            let loss = point.lossVsPrevious.map(display)
            let ahead = display(point.aheadOfPlan)
            let status = point.isWeekToDate ? " · WTD" : (point.isPartial ? " · partial" : "")
            let lossText: String? = loss.map { value in
                if value > 0.000_001 { return "\(valueText(value)) decrease" }
                if value < -0.000_001 { return "\(valueText(abs(value))) increase" }
                return "No change"
            }
            let compactLossText: String? = loss.map { value in
                if value > 0.000_001 { return String(format: "↓%.2f %@", locale: locale, value, unit.symbol) }
                if value < -0.000_001 { return String(format: "↑%.2f %@", locale: locale, abs(value), unit.symbol) }
                return String(format: "0.00 %@", locale: locale, unit.symbol)
            }
            let aheadText = ahead >= 0
                ? "\(valueText(abs(ahead))) ahead"
                : "\(valueText(abs(ahead))) behind"

            return Point(
                weekStart: point.weekStart,
                weekEnd: point.weekEnd,
                averageWeight: average,
                minWeight: minimum,
                maxWeight: maximum,
                readingCount: point.readingCount,
                lossVsPrevious: loss,
                plannedAverage: display(point.plannedAverage),
                aheadOfPlan: ahead,
                isPartial: point.isPartial,
                isWeekToDate: point.isWeekToDate,
                weekLabel: shortDate.string(from: point.weekStart),
                periodLabel: "\(shortDate.string(from: point.weekStart))–\(shortDate.string(from: point.weekEnd))\(status)",
                averageText: valueText(average),
                rangeText: String(format: "%.2f–%.2f %@", locale: locale, minimum, maximum, unit.symbol),
                lossText: lossText,
                lossValueText: loss.map { String(format: "%.2f", locale: locale, $0) },
                compactLossText: compactLossText,
                aheadText: aheadText,
                aheadValueText: String(format: "%+.2f", locale: locale, ahead)
            )
        }
        requiredWeeklyLoss = display(model.requiredWeeklyLoss)
        requiredWeeklyLossText = "\(valueText(display(model.requiredWeeklyLoss))) required / week"
        compactRequiredWeeklyLossText = String(
            format: "Req %.2f %@/wk",
            locale: locale,
            display(model.requiredWeeklyLoss),
            unit.symbol
        )
        averageWeightDomain = display(model.domains.averageWeight.lowerBound)...display(model.domains.averageWeight.upperBound)
        weeklyLossDomain = display(model.domains.weeklyLoss.lowerBound)...display(model.domains.weeklyLoss.upperBound)
        let fallback = Date(timeIntervalSince1970: 0)
        let firstWeek = points.first?.weekStart ?? fallback
        let lastWeek = points.last?.weekStart ?? fallback
        let domainStart = calendar.date(byAdding: .day, value: -2, to: firstWeek) ?? firstWeek
        let domainEnd = calendar.date(byAdding: .day, value: 3, to: lastWeek) ?? lastWeek
        weekDomain = domainStart...max(domainStart, domainEnd)
    }

    public func axisLabel(_ value: Double) -> String {
        String(format: abs(value) < 10 ? "%.1f" : "%.0f", value)
    }
}
