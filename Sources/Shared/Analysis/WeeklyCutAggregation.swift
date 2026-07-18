import Foundation

/// One Monday–Sunday calendar week of aggregated cut data. Shared by every
/// weekly chart mode so no view recomputes weekly statistics itself.
public struct WeeklyCutPoint: Identifiable, Equatable, Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    public let averageWeight: Double
    public let minWeight: Double
    public let maxWeight: Double
    public let readingCount: Int
    /// previousWeek.averageWeight - averageWeight (or the week-to-date
    /// matching-weekday equivalent for the current, incomplete week).
    /// Positive means average weight decreased. `nil` when there is no
    /// valid, comparable previous week.
    public let lossVsPrevious: Double?
    public let plannedAverage: Double
    /// plannedAverage - averageWeight. Positive means ahead of plan.
    public let aheadOfPlan: Double
    /// True when this week's observed range does not span a full Monday–
    /// Sunday week (clipped by the cut start date or by "today").
    public let isPartial: Bool
    /// True for the current, still-in-progress week.
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
}

/// Builds the single canonical weekly aggregation consumed by every weekly
/// chart mode. Weeks always run Monday through Sunday, regardless of where
/// the cut started or where "today" falls within a week.
public enum WeeklyCutAggregator {
    public static func aggregate(
        model: CutChartModel,
        asOf referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeeklyCutPoint] {
        let cutStart = calendar.startOfDay(for: model.startDate)
        let today = calendar.startOfDay(for: referenceDate)
        let horizon = min(today, calendar.startOfDay(for: model.targetDate))
        guard cutStart <= horizon else { return [] }

        let readingsByDate = Dictionary(
            uniqueKeysWithValues: model.raw.map { (calendar.startOfDay(for: $0.date), $0.value) }
        )
        let paceByDate = Dictionary(
            uniqueKeysWithValues: model.requiredPace.map { (calendar.startOfDay(for: $0.date), $0.value) }
        )

        var points: [WeeklyCutPoint] = []
        var weekStart = mondayWeekStart(for: cutStart, calendar: calendar)

        while weekStart <= horizon {
            guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { break }
            defer {
                weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekEnd
            }

            let periodStart = max(weekStart, cutStart)
            let periodEnd = min(weekEnd, horizon)
            guard periodStart <= periodEnd else { continue }

            let observedDates = dailyDates(from: periodStart, through: periodEnd, calendar: calendar)
                .filter { readingsByDate[$0] != nil }
            guard !observedDates.isEmpty else { continue }

            let isCutStartClipped = periodStart > weekStart
            let isEndClipped = periodEnd < weekEnd
            let isCurrentWeek = weekStart <= today && today <= weekEnd
            let isWeekToDate = isCurrentWeek && isEndClipped
            let isPartial = isCutStartClipped || isEndClipped

            let values = observedDates.map { readingsByDate[$0]! }
            let average = values.reduce(0, +) / Double(values.count)
            let minWeight = values.min() ?? average
            let maxWeight = values.max() ?? average
            let plannedValues = observedDates.compactMap { paceByDate[$0] }
            let plannedAverage = plannedValues.isEmpty ? average : plannedValues.reduce(0, +) / Double(plannedValues.count)
            let aheadOfPlan = plannedAverage - average

            let lossVsPrevious: Double?
            if isWeekToDate {
                lossVsPrevious = weekToDateLoss(
                    currentWeekStart: weekStart,
                    currentAverage: average,
                    observedDates: observedDates,
                    readingsByDate: readingsByDate,
                    calendar: calendar
                )
            } else if let previous = points.last,
                      !previous.isPartial,
                      calendar.date(byAdding: .day, value: 7, to: previous.weekStart) == weekStart {
                lossVsPrevious = previous.averageWeight - average
            } else {
                lossVsPrevious = nil
            }

            points.append(WeeklyCutPoint(
                weekStart: weekStart,
                weekEnd: weekEnd,
                averageWeight: average,
                minWeight: minWeight,
                maxWeight: maxWeight,
                readingCount: observedDates.count,
                lossVsPrevious: lossVsPrevious,
                plannedAverage: plannedAverage,
                aheadOfPlan: aheadOfPlan,
                isPartial: isPartial,
                isWeekToDate: isWeekToDate
            ))
        }

        return points
    }

    /// Week-to-date comparison: the current week's average so far versus the
    /// previous week's average restricted to the same matching weekdays
    /// (e.g. Mon–Fri vs. the prior Mon–Fri).
    private static func weekToDateLoss(
        currentWeekStart: Date,
        currentAverage: Double,
        observedDates: [Date],
        readingsByDate: [Date: Double],
        calendar: Calendar
    ) -> Double? {
        guard let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) else {
            return nil
        }
        let offsets = observedDates.compactMap {
            calendar.dateComponents([.day], from: currentWeekStart, to: $0).day
        }
        let matchingPreviousDates = offsets.compactMap {
            calendar.date(byAdding: .day, value: $0, to: previousWeekStart)
        }
        let matchingValues = matchingPreviousDates.compactMap { readingsByDate[$0] }
        guard !matchingValues.isEmpty else { return nil }
        let previousAverage = matchingValues.reduce(0, +) / Double(matchingValues.count)
        return previousAverage - currentAverage
    }

    private static func mondayWeekStart(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // Sunday = 1 ... Saturday = 7
        let offset = weekday == 1 ? -6 : -(weekday - 2)
        return calendar.date(byAdding: .day, value: offset, to: day) ?? day
    }

    private static func dailyDates(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        guard start <= end else { return [] }
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

public extension CutChartModel {
    /// Required weekly rate of loss for the whole cut: (start - target) / duration in weeks.
    var requiredWeeklyRateLb: Double {
        let durationDays = targetDate.timeIntervalSince(startDate) / 86_400
        let weeks = durationDays / 7
        guard weeks > 0 else { return 0 }
        return (startWeightLb - targetWeightLb) / weeks
    }
}
