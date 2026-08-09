import XCTest
@testable import WeightTracker

@MainActor
final class TodayLensModelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ value: String, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? self.calendar
        return Reading.date(fromCivilDayKey: value, calendar: calendar)!
    }

    private func reading(_ day: String, pounds: Double, source: ReadingSource = .importCSV) -> Reading {
        Reading(
            date: date(day),
            weightKg: UnitConvert.lbToKg(pounds),
            source: source,
            civilDayKey: day,
            calendar: calendar
        )
    }

    private var cut: ActiveCut {
        ActiveCut(
            startDate: date("2026-04-28"),
            startWeightKg: UnitConvert.lbToKg(174.5),
            targetWeightKg: UnitConvert.lbToKg(150),
            targetEndDate: date("2026-08-21")
        )
    }

    /// Six prior-window readings (mean 154.8) plus the supplied Aug 2-8
    /// observations. Jul 31 and Aug 5 are intentionally absent.
    private var acceptanceReadings: [Reading] {
        [
            ("2026-07-26", 155.3),
            ("2026-07-27", 155.1),
            ("2026-07-28", 154.9),
            ("2026-07-29", 154.7),
            ("2026-07-30", 154.6),
            ("2026-08-01", 154.2),
            ("2026-08-02", 154.8),
            ("2026-08-03", 153.7),
            ("2026-08-04", 153.4),
            ("2026-08-06", 153.6),
            ("2026-08-07", 152.8),
            ("2026-08-08", 153.4),
        ].map { reading($0.0, pounds: $0.1) }
    }

    private var analytics: TodayAnalyticsModel {
        TodayAnalyticsModel.prepare(
            active: cut,
            readings: acceptanceReadings,
            asOf: date("2026-08-09"),
            calendar: calendar
        )
    }

    func testAcceptanceFixtureSeparatesTrailingSevenDaysFromCalendarWeek() throws {
        let model = analytics
        XCTAssertEqual(try XCTUnwrap(model.latestObservation).value, 153.4, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(model.currentTrend).value, 153.616_666_7, accuracy: 0.000_001)
        XCTAssertEqual(model.currentTrendObservationCount, 6)

        let weekly = WeeklyCutChartModel.prepare(
            active: cut,
            readings: acceptanceReadings,
            asOf: date("2026-08-09"),
            calendar: calendar
        )
        let week = try XCTUnwrap(weekly.points.first { $0.weekStart == date("2026-08-03") })
        XCTAssertEqual(week.readingCount, 5)
        XCTAssertEqual(week.averageWeight, 153.38, accuracy: 0.000_001)
        XCTAssertEqual(week.minWeight, 152.8, accuracy: 0.000_001)
        XCTAssertEqual(week.maxWeight, 153.7, accuracy: 0.000_001)
    }

    func testAcceptanceFixturePacePlanAndNeededNow() throws {
        let model = analytics
        let fit = try XCTUnwrap(model.recentPace)
        XCTAssertEqual(fit.signedLbPerWeek, -1.186_05, accuracy: 0.01)
        XCTAssertEqual(fit.observationCount, 12)
        XCTAssertEqual(model.plannedWeightAsOfLb, 152.556_522, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(model.trendMinusPlanLb), 1.060_145, accuracy: 0.000_01)
        guard case .available(let needed) = model.neededNow else {
            return XCTFail("expected available needed-now pace")
        }
        XCTAssertEqual(needed, 2.109_722, accuracy: 0.000_01)
    }

    func testMissingDaysAreNotFilledOrDuplicated() throws {
        let sparse = [
            reading("2026-08-02", pounds: 154.8),
            reading("2026-08-04", pounds: 153.4),
            reading("2026-08-08", pounds: 153.4),
        ]
        let model = TodayAnalyticsModel.prepare(
            active: cut,
            readings: sparse,
            asOf: date("2026-08-09"),
            calendar: calendar
        )
        XCTAssertEqual(model.observations.count, 3)
        XCTAssertEqual(model.currentTrendObservationCount, 3)
        XCTAssertEqual(try XCTUnwrap(model.currentTrend).value, (154.8 + 153.4 + 153.4) / 3, accuracy: 0.000_001)
    }

    func testManualDuplicateWinsAndSameSourceDuplicatesAverage() throws {
        let values = [
            reading("2026-08-08", pounds: 160, source: .healthKit),
            reading("2026-08-08", pounds: 153, source: .manual),
            reading("2026-08-08", pounds: 154, source: .manual),
        ]
        let daily = CanonicalDailyWeightSeries.prepare(readings: values, calendar: calendar)
        XCTAssertEqual(daily.count, 1)
        XCTAssertEqual(UnitConvert.kgToLb(try XCTUnwrap(daily.first).weightKg), 153.5, accuracy: 0.000_001)
    }

    func testOneOrTwoRecentReadingsDoNotClaimAPace() {
        for count in 1...2 {
            let readings = Array(acceptanceReadings.suffix(count))
            let model = TodayAnalyticsModel.prepare(
                active: cut,
                readings: readings,
                asOf: date("2026-08-09"),
                calendar: calendar
            )
            XCTAssertNil(model.recentPace)
            XCTAssertNil(model.forecast)
        }
    }

    func testCivilDaySurvivesTimezoneAndDSTReconstruction() throws {
        var athens = Calendar(identifier: .gregorian)
        athens.timeZone = TimeZone(identifier: "Europe/Athens")!
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let reading = Reading(
            date: date("2026-08-08", calendar: athens),
            weightKg: 70,
            civilDayKey: "2026-08-08",
            calendar: athens
        )
        XCTAssertEqual(Reading.civilDayKey(for: reading.dayStart(in: losAngeles), calendar: losAngeles), "2026-08-08")

        let springStart = date("2026-03-07", calendar: losAngeles)
        let springEnd = date("2026-03-10", calendar: losAngeles)
        let midpoint = date("2026-03-08", calendar: losAngeles)
        XCTAssertEqual(
            CutChartModel.requiredPace(
                at: midpoint,
                startDate: springStart,
                targetDate: springEnd,
                startWeight: 180,
                targetWeight: 174,
                calendar: losAngeles
            ),
            178,
            accuracy: 0.000_001
        )
    }

    func testGoalReachedAndDeadlinePassedAreDistinct() {
        let reached = TodayAnalyticsModel.prepare(
            active: cut,
            readings: [reading("2026-08-08", pounds: 149.8)],
            asOf: date("2026-08-09"),
            calendar: calendar
        )
        XCTAssertEqual(reached.neededNow, .goalReached)

        var expired = cut
        expired.targetEndDate = date("2026-08-08")
        let late = TodayAnalyticsModel.prepare(
            active: expired,
            readings: [reading("2026-08-08", pounds: 153.4)],
            asOf: date("2026-08-09"),
            calendar: calendar
        )
        XCTAssertEqual(late.neededNow, .deadlinePassed)
    }

    func testVeryShortHorizonIsFiniteAndGoalChangesRecomputeNeededPace() throws {
        var short = cut
        short.targetEndDate = date("2026-08-10")
        let shortModel = TodayAnalyticsModel.prepare(active: short, readings: acceptanceReadings, asOf: date("2026-08-09"), calendar: calendar)
        guard case .available(let oneDayNeeded) = shortModel.neededNow else {
            return XCTFail("expected finite one-day pace")
        }
        XCTAssertTrue(oneDayNeeded.isFinite)

        var easier = cut
        easier.targetWeightKg = UnitConvert.lbToKg(152)
        easier.targetEndDate = date("2026-08-28")
        let changed = TodayAnalyticsModel.prepare(active: easier, readings: acceptanceReadings, asOf: date("2026-08-09"), calendar: calendar)
        guard case .available(let changedNeeded) = changed.neededNow else {
            return XCTFail("expected recalculated pace")
        }
        XCTAssertLessThan(changedNeeded, oneDayNeeded)
        XCTAssertNotEqual(changed.plannedWeightAsOfLb, analytics.plannedWeightAsOfLb)
    }

    func testWaterSpikeAndLowOutlierRemainObservedRatherThanInterpolated() throws {
        var readings = acceptanceReadings
        readings.append(reading("2026-08-09", pounds: 157.4)) // temporary +4 lb spike
        readings.append(reading("2026-08-10", pounds: 150.4)) // anomalously low
        let model = TodayAnalyticsModel.prepare(active: cut, readings: readings, asOf: date("2026-08-10"), calendar: calendar)
        XCTAssertEqual(model.observations.suffix(2).map(\.value), [157.4, 150.4])
        XCTAssertTrue(try XCTUnwrap(model.currentTrend).value > 150.4)
        XCTAssertTrue(try XCTUnwrap(model.currentTrend).value < 157.4)
    }

    func testFlatAndGainingSeriesKeepConventionalSignedSlopes() throws {
        let days = (1...14).map { String(format: "2026-07-%02d", $0) }
        let flat = days.map { reading($0, pounds: 160) }
        let gaining = days.enumerated().map { reading($0.element, pounds: 160 + Double($0.offset) * 0.1) }
        let flatModel = TodayAnalyticsModel.prepare(active: cut, readings: flat, asOf: date("2026-07-14"), calendar: calendar)
        let gainingModel = TodayAnalyticsModel.prepare(active: cut, readings: gaining, asOf: date("2026-07-14"), calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(flatModel.recentPace).signedLbPerWeek, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(try XCTUnwrap(gainingModel.recentPace).signedLbPerWeek, 0)
    }
}
