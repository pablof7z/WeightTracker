import XCTest
@testable import WeightTracker

@MainActor
final class WeeklyCutAggregationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }

    /// Cut starts on a Wednesday (2026-04-29) so the first calendar week is
    /// partial, and runs for four full weeks to 2026-05-27 (a Wednesday).
    private var cut: ActiveCut {
        ActiveCut(
            startDate: date("2026-04-29"),
            startWeightKg: UnitConvert.lbToKg(180),
            targetWeightKg: UnitConvert.lbToKg(160),
            targetEndDate: date("2026-05-27")
        )
    }

    private var projection: CutProjectionResult {
        CutProjectionResult(
            anchorDate: date("2026-05-20"),
            anchorKg: UnitConvert.lbToKg(174),
            isTargetReached: false,
            qualifyingHistoricalCount: 0,
            bestEndKg: nil,
            avgPath: [],
            worstEndKg: nil,
            targetWeightKg: UnitConvert.lbToKg(160),
            targetEndDate: date("2026-05-27")
        )
    }

    /// Loses a steady 0.3 lb/day from 2026-04-29 through 2026-05-20, skipping
    /// 2026-05-05 to exercise a missing day within a week.
    private func fixtureReadings(skip: Set<String> = ["2026-05-05"]) -> [Reading] {
        var readings: [Reading] = []
        var day = date("2026-04-29")
        let end = date("2026-05-20")
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var offset = 0
        while day <= end {
            let key = formatter.string(from: day)
            if !skip.contains(key) {
                readings.append(Reading(date: day, weightKg: UnitConvert.lbToKg(180 - Double(offset) * 0.3), source: .manual))
            }
            offset += 1
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return readings
    }

    private func prepared(readings: [Reading]) -> CutChartModel {
        CutChartModel.prepare(active: cut, readings: readings, projection: projection, calendar: calendar)
    }

    private func aggregate(readings: [Reading]? = nil, asOf: String = "2026-05-20") -> [WeeklyCutPoint] {
        let model = prepared(readings: readings ?? fixtureReadings())
        return WeeklyCutAggregator.aggregate(model: model, asOf: date(asOf), calendar: calendar)
    }

    func testFirstWeekIsPartialAndNotComparable() {
        let points = aggregate()
        let firstWeek = points[0]
        XCTAssertEqual(firstWeek.weekStart, date("2026-04-27")) // Monday
        XCTAssertEqual(firstWeek.weekEnd, date("2026-05-03"))   // Sunday
        XCTAssertTrue(firstWeek.isPartial)
        XCTAssertFalse(firstWeek.isWeekToDate)
        // Only Apr 29, 30, May 1-3 have data (cut starts mid-week).
        XCTAssertEqual(firstWeek.readingCount, 5)
        XCTAssertNil(firstWeek.lossVsPrevious, "No prior week exists within the cut")
    }

    func testWeekFollowingThePartialStartWeekIsNotComparable() {
        let points = aggregate()
        // Second week (May 4-10) is a full Mon-Sun week, but its predecessor
        // was the cut-start partial week, so it must not present a loss.
        let secondWeek = points[1]
        XCTAssertEqual(secondWeek.weekStart, date("2026-05-04"))
        XCTAssertFalse(secondWeek.isPartial)
        XCTAssertNil(secondWeek.lossVsPrevious, "Partial start week must not be compared against a full week")
    }

    func testMissingDayIsExcludedFromAverageButWeekStillReported() {
        let points = aggregate()
        let secondWeek = points[1] // May 4-10, missing May 5
        XCTAssertEqual(secondWeek.readingCount, 6)
        // Values for May4,6,7,8,9,10 (offsets 5,7,8,9,10,11 lb loss from 180 at 0.3/day)
        let expectedAverage = [5, 7, 8, 9, 10, 11].map { 180 - Double($0) * 0.3 }.reduce(0, +) / 6
        XCTAssertEqual(secondWeek.averageWeight, expectedAverage, accuracy: 0.000_001)
    }

    func testTwoFullWeeksProduceExactWeeklyLossWithCorrectSign() {
        let points = aggregate()
        // Third week (May 11-17) follows a full second week (May 4-10); loss should be reported.
        let secondWeek = points[1]
        let thirdWeek = points[2]
        XCTAssertFalse(thirdWeek.isPartial)
        XCTAssertNotNil(thirdWeek.lossVsPrevious)
        XCTAssertEqual(thirdWeek.lossVsPrevious!, secondWeek.averageWeight - thirdWeek.averageWeight, accuracy: 0.000_001)
        // Weight is steadily decreasing, so the loss must be positive.
        XCTAssertGreaterThan(thirdWeek.lossVsPrevious!, 0)
    }

    func testWeekToDateComparesOnlyMatchingWeekdays() {
        // asOf 2026-05-20 is a Wednesday; the current week (May 18-24) has
        // readings for Mon, Tue, Wed only.
        let points = aggregate()
        let currentWeek = points.last!
        XCTAssertEqual(currentWeek.weekStart, date("2026-05-18"))
        XCTAssertTrue(currentWeek.isWeekToDate)
        XCTAssertTrue(currentWeek.isPartial)
        XCTAssertEqual(currentWeek.readingCount, 3) // Mon 18, Tue 19, Wed 20

        // Expected: previous week's Mon-Wed (May 11-13) average vs this week's Mon-Wed average.
        let priorWeek = points[points.count - 2]
        XCTAssertEqual(priorWeek.weekStart, date("2026-05-11"))

        let currentMonWedAvg = currentWeek.averageWeight
        // Manually compute previous week's Mon(11)-Wed(13) average from the model.
        let model = prepared(readings: fixtureReadings())
        let matching = model.raw.filter { [date("2026-05-11"), date("2026-05-12"), date("2026-05-13")].contains($0.date) }
        let priorMonWedAvg = matching.map(\.value).reduce(0, +) / Double(matching.count)

        XCTAssertNotNil(currentWeek.lossVsPrevious)
        XCTAssertEqual(currentWeek.lossVsPrevious!, priorMonWedAvg - currentMonWedAvg, accuracy: 0.000_001)
    }

    func testWeekToDateReturnsNilWhenNoMatchingPreviousWeekdaysHaveReadings() {
        // Remove all of the previous week's Mon-Wed readings so there is no
        // matching-weekday data to compare the current WTD week against.
        let readings = fixtureReadings(skip: ["2026-05-05", "2026-05-11", "2026-05-12", "2026-05-13"])
        let points = aggregate(readings: readings)
        let currentWeek = points.last!
        XCTAssertTrue(currentWeek.isWeekToDate)
        XCTAssertNil(currentWeek.lossVsPrevious)
    }

    func testAheadOfPlanUsesPlannedMinusActualAndPositiveMeansAhead() {
        // Losing 0.3 lb/day (~2.1 lb/week) is slower than the ~5 lb/week
        // required pace over the four-week cut, so every week should be
        // behind plan (aheadOfPlan < 0).
        let points = aggregate()
        for point in points {
            XCTAssertEqual(point.aheadOfPlan, point.plannedAverage - point.averageWeight, accuracy: 0.000_001)
            XCTAssertLessThan(point.aheadOfPlan, 0, "Losing weight slower than required should be behind plan")
        }
    }

    func testRequiredWeeklyRateIsStartMinusTargetOverDurationInWeeks() {
        let model = prepared(readings: fixtureReadings())
        let expected = (180.0 - 160.0) / (28.0 / 7.0)
        XCTAssertEqual(model.requiredWeeklyRateLb, expected, accuracy: 0.000_001)
    }

    func testMinAndMaxWeightBoundTheAverage() {
        let points = aggregate()
        for point in points {
            XCTAssertLessThanOrEqual(point.minWeight, point.averageWeight)
            XCTAssertGreaterThanOrEqual(point.maxWeight, point.averageWeight)
        }
    }

    func testNoPointsBeforeCutStart() {
        let points = aggregate()
        XCTAssertTrue(points.allSatisfy { $0.weekEnd >= date("2026-04-29") })
    }
}
