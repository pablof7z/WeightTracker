import XCTest
@testable import WeightTracker

@MainActor
final class TodayLensModelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: value)!
    }

    private func reading(_ day: String, pounds: Double, source: ReadingSource = .importCSV) -> Reading {
        let exact = date(day)
        let r = Reading(date: exact, weightKg: UnitConvert.lbToKg(pounds), source: source)
        r.date = exact
        return r
    }

    // MARK: - Least squares

    func testLeastSquaresSlopeMatchesKnownLinearData() {
        // 180 lb declining 0.2 lb/day for 10 days.
        let points = (0..<10).map { i in
            DatedValue(date: date("2026-05-01").addingTimeInterval(Double(i) * 86_400), value: 180 - 0.2 * Double(i))
        }
        let slope = PaceLensModel.leastSquaresSlopePerDay(points, calendar: calendar)!
        XCTAssertEqual(slope, -0.2, accuracy: 1e-9)
    }

    // MARK: - Pace lens

    private func decliningCut() -> (ActiveCut, [Reading], CutProjectionResult) {
        // 20 days declining exactly 0.2 lb/day from 180.
        let readings = (0..<20).map { i in
            reading(dayString(offset: i), pounds: 180 - 0.2 * Double(i))
        }
        let start = date("2026-05-01")
        let end = calendar.date(byAdding: .day, value: 140, to: start)!
        let cut = ActiveCut(
            startDate: start,
            startWeightKg: UnitConvert.lbToKg(180),
            targetWeightKg: UnitConvert.lbToKg(160),
            targetEndDate: end
        )
        let anchorDate = date(dayString(offset: 19))
        let projection = CutProjectionResult(
            anchorDate: anchorDate,
            anchorKg: UnitConvert.lbToKg(176.2),
            isTargetReached: false,
            qualifyingHistoricalCount: 2,
            bestEndKg: UnitConvert.lbToKg(158),
            avgPath: [(anchorDate, UnitConvert.lbToKg(176.2)), (end, UnitConvert.lbToKg(159))],
            worstEndKg: UnitConvert.lbToKg(161),
            targetWeightKg: UnitConvert.lbToKg(160),
            targetEndDate: end
        )
        return (cut, readings, projection)
    }

    private func dayString(offset: Int) -> String {
        let d = calendar.date(byAdding: .day, value: offset, to: date("2026-05-01"))!
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    func testPaceIsTrailingRegressionExpressedAsPositiveLbPerWeek() {
        let (cut, readings, projection) = decliningCut()
        let model = PaceLensModel.prepare(
            active: cut, readings: readings, projection: projection,
            asOf: date(dayString(offset: 19)), calendar: calendar
        )
        // −0.2 lb/day × 7 = 1.4 lb/week of loss, positive.
        XCTAssertEqual(model.latest!, 1.4, accuracy: 1e-6)
        XCTAssertGreaterThan(model.latest!, 0)
    }

    func testPaceRequiredConstantMatchesPlan() {
        let (cut, readings, projection) = decliningCut()
        let model = PaceLensModel.prepare(active: cut, readings: readings, projection: projection,
                                          asOf: date(dayString(offset: 19)), calendar: calendar)
        // (180 − 160) over 140 days = 20 weeks → 1.0 lb/week.
        XCTAssertEqual(model.requiredConstant, 1.0, accuracy: 1e-9)
        XCTAssertEqual(model.projectedTargetWeightLb!, 159, accuracy: 1e-6)
    }

    func testAddingFutureReadingDoesNotRewriteEarlierPace() {
        let (cut, readings, projection) = decliningCut()
        let before = PaceLensModel.prepare(active: cut, readings: readings, projection: projection,
                                           asOf: date(dayString(offset: 19)), calendar: calendar)
        var extended = readings
        extended.append(reading(dayString(offset: 20), pounds: 175.6))
        let after = PaceLensModel.prepare(active: cut, readings: extended, projection: projection,
                                          asOf: date(dayString(offset: 20)), calendar: calendar)
        let lastOld = before.actual.last!.date
        let beforeUpTo = before.actual.filter { $0.date <= lastOld }
        let afterUpTo = after.actual.filter { $0.date <= lastOld }
        XCTAssertEqual(beforeUpTo, afterUpTo)
    }

    // MARK: - This Week lens

    private func weekCut() -> ActiveCut {
        ActiveCut(
            startDate: date("2026-07-01"),
            startWeightKg: UnitConvert.lbToKg(170),
            targetWeightKg: UnitConvert.lbToKg(150),
            targetEndDate: date("2026-09-01")
        )
    }

    func testThisWeekBaselineIsLastReadingBeforeTheWeek() {
        let readings = [
            reading("2026-07-12", pounds: 160.0), // Sunday, pre-week baseline
            reading("2026-07-13", pounds: 159.5), // Monday
            reading("2026-07-14", pounds: 159.0),
            reading("2026-07-15", pounds: 158.5), // asOf Wednesday
        ]
        let model = ThisWeekModel.prepare(active: weekCut(), readings: readings, asOf: date("2026-07-15"), calendar: calendar)
        XCTAssertEqual(model.weekStart, date("2026-07-13"))
        XCTAssertEqual(model.baselineLb!, 160.0, accuracy: 1e-9)
        XCTAssertFalse(model.isPartial)
        XCTAssertEqual(model.daysLogged, 3)
    }

    func testThisWeekHeadlineEqualsFinalCumulativePoint() {
        let readings = [
            reading("2026-07-12", pounds: 160.0),
            reading("2026-07-13", pounds: 159.5),
            reading("2026-07-14", pounds: 159.0),
            reading("2026-07-15", pounds: 158.5),
        ]
        let model = ThisWeekModel.prepare(active: weekCut(), readings: readings, asOf: date("2026-07-15"), calendar: calendar)
        XCTAssertEqual(model.headline!, -1.5, accuracy: 1e-9)
        XCTAssertEqual(model.points.last!.value, model.headline!, accuracy: 1e-12)
        XCTAssertEqual(model.weekAverageLb!, 159.0, accuracy: 1e-9)
        XCTAssertEqual(model.avgPerDay!, -0.5, accuracy: 1e-9)
    }

    func testThisWeekIsPartialWithoutAPriorBaseline() {
        let readings = [
            reading("2026-07-13", pounds: 159.5),
            reading("2026-07-14", pounds: 159.0),
            reading("2026-07-15", pounds: 158.5),
        ]
        let model = ThisWeekModel.prepare(active: weekCut(), readings: readings, asOf: date("2026-07-15"), calendar: calendar)
        XCTAssertTrue(model.isPartial)
        XCTAssertEqual(model.baselineLb!, 159.5, accuracy: 1e-9)
        XCTAssertEqual(model.headline!, -1.0, accuracy: 1e-9)
    }

    func testThisWeekMissingDaysAreNotInterpolated() {
        let readings = [
            reading("2026-07-12", pounds: 160.0),
            reading("2026-07-13", pounds: 159.5),
            // Tuesday intentionally missing
            reading("2026-07-15", pounds: 158.5),
        ]
        let model = ThisWeekModel.prepare(active: weekCut(), readings: readings, asOf: date("2026-07-15"), calendar: calendar)
        XCTAssertEqual(model.points.count, 2)
        XCTAssertEqual(model.daysLogged, 2)
    }

    func testThisWeekYDomainIsFixedUntilExceeded() {
        let small = ThisWeekModel.prepare(active: weekCut(), readings: [
            reading("2026-07-12", pounds: 160.0),
            reading("2026-07-13", pounds: 159.5),
        ], asOf: date("2026-07-15"), calendar: calendar)
        XCTAssertEqual(small.yDomain.lowerBound, -4, accuracy: 1e-9)
        XCTAssertEqual(small.yDomain.upperBound, 4, accuracy: 1e-9)

        let big = ThisWeekModel.prepare(active: weekCut(), readings: [
            reading("2026-07-12", pounds: 160.0),
            reading("2026-07-13", pounds: 153.5), // −6.5, exceeds ±4
        ], asOf: date("2026-07-15"), calendar: calendar)
        XCTAssertGreaterThanOrEqual(big.yDomain.upperBound, 6.5)
    }

    // MARK: - Lens hero acceptance criteria (1, 2, 3)

    func testLensHeroesMatchCanonicalValues() {
        let (cut, readings, projection) = decliningCut()
        let asOf = date(dayString(offset: 19))
        let chart = CutChartModel.prepare(active: cut, readings: readings, projection: projection, calendar: calendar)
        let domains = CutChartDomainState.resolved(for: chart, calendar: calendar)
        let weekly = WeeklyCutChartModel.prepare(active: cut, readings: readings, asOf: asOf, calendar: calendar)
        let pace = PaceLensModel.prepare(active: cut, readings: readings, projection: projection, asOf: asOf, calendar: calendar)
        let thisWeek = ThisWeekModel.prepare(active: cut, readings: readings, asOf: asOf, calendar: calendar)

        let builder = TodayLensBuilder(
            active: cut, projection: projection, chart: chart, domains: domains,
            weekly: weekly, pace: pace, thisWeek: thisWeek, unit: .lbs, dayNumber: 20, calendar: calendar
        )

        // 1. Current Weight headline == the last canonical raw point.
        let last = chart.raw.last!.value
        XCTAssertEqual(builder.render(.currentWeight).heroValue, String(format: "%.1f", last))

        // 2. Total Lost headline == start − latest canonical weight.
        XCTAssertEqual(builder.render(.totalLost).heroValue, String(format: "%.1f", chart.startWeightLb - last))

        // 3. This Week headline == final weekly cumulative-change point.
        let tw = builder.render(.thisWeek)
        if let headline = thisWeek.headline {
            XCTAssertEqual(tw.heroValue, String(format: "%+.1f", headline))
        }
    }
}
