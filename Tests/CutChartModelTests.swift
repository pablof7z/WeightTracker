import XCTest
@testable import WeightTracker

@MainActor
final class CutChartModelTests: XCTestCase {
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

    private var cut: ActiveCut {
        ActiveCut(
            startDate: date("2026-04-28"),
            startWeightKg: UnitConvert.lbToKg(174.5),
            targetWeightKg: UnitConvert.lbToKg(150),
            targetEndDate: date("2026-08-21")
        )
    }

    private var fixtureReadings: [Reading] {
        let fixture = """
        2026-04-28,174.5
        2026-04-29,174.2
        2026-04-30,173.7
        2026-05-01,173.4
        2026-05-02,174.2
        2026-05-03,174.2
        2026-05-04,173.7
        2026-05-05,173.2
        2026-05-06,174.0
        2026-05-07,173.3
        2026-05-08,173.7
        2026-05-09,173.1
        2026-05-10,173.6
        2026-05-11,172.5
        2026-05-12,172.0
        2026-05-13,171.8
        2026-05-14,171.3
        2026-05-15,170.0
        2026-05-16,170.0
        2026-05-17,171.6
        2026-05-18,170.6
        2026-05-19,169.2
        2026-05-20,168.6
        2026-05-21,168.4
        2026-05-22,168.4
        2026-05-23,169.4
        2026-05-24,168.4
        2026-05-25,168.6
        2026-05-26,167.6
        2026-05-27,167.2
        2026-05-28,166.6
        2026-05-29,165.6
        2026-05-30,164.6
        2026-05-31,164.7
        2026-06-01,163.5
        2026-06-02,163.1
        2026-06-03,163.9
        2026-06-05,164.7
        2026-06-06,165.3
        2026-06-07,164.6
        2026-06-08,166.4
        2026-06-09,165.4
        2026-06-10,164.4
        2026-06-11,163.6
        2026-06-12,162.6
        2026-06-13,162.2
        2026-06-14,162.6
        2026-06-15,165.0
        2026-06-16,162.2
        2026-06-17,162.2
        2026-06-18,161.5
        2026-06-20,162.5
        2026-06-21,162.4
        2026-06-22,161.8
        2026-06-23,160.8
        2026-06-24,160.9
        2026-06-25,158.8
        2026-06-26,159.8
        2026-06-27,161.0
        2026-06-28,161.4
        2026-06-30,159.8
        2026-07-01,160.4
        2026-07-02,159.8
        2026-07-03,159.0
        2026-07-04,158.9
        2026-07-05,159.8
        2026-07-06,159.3
        2026-07-07,159.4
        2026-07-08,157.4
        2026-07-09,158.0
        2026-07-10,157.8
        2026-07-11,157.3
        2026-07-12,157.0
        2026-07-13,157.4
        2026-07-14,155.8
        2026-07-15,155.0
        2026-07-16,156.9
        2026-07-17,156.2
        """
        return fixture.split(separator: "\n").map { row in
            let columns = row.split(separator: ",")
            return Reading(
                date: date(String(columns[0])),
                weightKg: UnitConvert.lbToKg(Double(columns[1])!),
                source: .importCSV
            )
        }
    }

    private var projection: CutProjectionResult {
        let anchorDate = date("2026-07-17")
        let anchorKg = UnitConvert.lbToKg(156.64)
        return CutProjectionResult(
            anchorDate: anchorDate,
            anchorKg: anchorKg,
            isTargetReached: false,
            qualifyingHistoricalCount: 2,
            bestEndKg: UnitConvert.lbToKg(148.325),
            avgPath: [
                (anchorDate, anchorKg),
                (date("2026-07-18"), UnitConvert.lbToKg(156.4)),
                (date("2026-08-21"), UnitConvert.lbToKg(150.3)),
            ],
            worstEndKg: UnitConvert.lbToKg(153.4),
            targetWeightKg: UnitConvert.lbToKg(150),
            targetEndDate: date("2026-08-21")
        )
    }

    private func prepared(readings: [Reading]? = nil) -> CutChartModel {
        CutChartModel.prepare(
            active: cut,
            readings: readings ?? fixtureReadings,
            projection: projection,
            calendar: calendar
        )
    }

    func testFixtureMatchesHandoffValues() {
        let model = prepared()
        XCTAssertEqual(model.raw.last!.value, 156.2, accuracy: 0.000_001)
        XCTAssertEqual(model.trailing7.last!.value, 156.514_286, accuracy: 0.000_001)
        XCTAssertEqual(model.forecastAnchor.value, 156.64, accuracy: 0.000_001)
        XCTAssertEqual(model.requiredPaceValue(at: date("2026-07-17")), 157.456_522, accuracy: 0.000_001)
    }

    func testCanonicalDayPrefersManualReading() {
        var readings = fixtureReadings
        readings.append(Reading(date: date("2026-07-17"), weightKg: UnitConvert.lbToKg(160), source: .healthKit))
        readings.append(Reading(date: date("2026-07-17"), weightKg: UnitConvert.lbToKg(156.2), source: .manual))
        let model = prepared(readings: readings)
        XCTAssertEqual(model.raw.filter { $0.date == date("2026-07-17") }.count, 1)
        XCTAssertEqual(model.raw.last!.value, 156.2, accuracy: 0.000_001)
    }

    func testAppendingReadingDoesNotChangeFullCutXDomains() {
        let model = prepared()
        let state = CutChartDomainState.resolved(for: model, calendar: calendar)
        var readings = fixtureReadings
        readings.append(Reading(date: date("2026-07-18"), weightKg: UnitConvert.lbToKg(156), source: .manual))
        let appended = prepared(readings: readings)
        let appendedState = CutChartDomainState.resolved(for: appended, previous: state, calendar: calendar)

        for variation in CutChartVariation.allCases where variation != .recentFocus {
            let before = CutChartTransformer.transform(model, variation: variation, domains: state, calendar: calendar)
            let after = CutChartTransformer.transform(appended, variation: variation, domains: appendedState, calendar: calendar)
            XCTAssertEqual(before.xDomain, after.xDomain, "\(variation) changed its fixed x-domain")
        }
    }

    func testStableYDomainOnlyExpandsAndNeverContracts() {
        let model = prepared()
        let initial = CutChartDomainState.resolved(for: model, calendar: calendar)
        var inRange = fixtureReadings
        inRange.append(Reading(date: date("2026-07-18"), weightKg: UnitConvert.lbToKg(156), source: .manual))
        let unchanged = CutChartDomainState.resolved(for: prepared(readings: inRange), previous: initial, calendar: calendar)
        XCTAssertEqual(initial.absoluteLower, unchanged.absoluteLower)
        XCTAssertEqual(initial.absoluteUpper, unchanged.absoluteUpper)

        var outlier = fixtureReadings
        outlier.append(Reading(date: date("2026-07-18"), weightKg: UnitConvert.lbToKg(180), source: .manual))
        let expanded = CutChartDomainState.resolved(for: prepared(readings: outlier), previous: initial, calendar: calendar)
        XCTAssertGreaterThan(expanded.absoluteUpper, initial.absoluteUpper)

        let retained = CutChartDomainState.resolved(for: model, previous: expanded, calendar: calendar)
        XCTAssertEqual(retained.absoluteUpper, expanded.absoluteUpper)
    }

    func testOnePoundHasConstantTransformedImpactAtEveryDate() {
        let model = prepared()
        let state = CutChartDomainState.resolved(for: model, calendar: calendar)
        let earlyIndex = model.raw.firstIndex { $0.date == date("2026-05-10") }!
        let lateIndex = model.raw.firstIndex { $0.date == date("2026-07-10") }!

        for variation in [CutChartVariation.fixedFullCut, .remainingToGoal, .cumulativeLoss, .paceDelta] {
            let transformed = CutChartTransformer.transform(model, variation: variation, domains: state, calendar: calendar)
            let early = transformed.raw[earlyIndex].value
            let late = transformed.raw[lateIndex].value
            let earlyShift = transformedValue(weight: model.raw[earlyIndex].value + 1, date: model.raw[earlyIndex].date, variation: variation, model: model)
            let lateShift = transformedValue(weight: model.raw[lateIndex].value + 1, date: model.raw[lateIndex].date, variation: variation, model: model)
            XCTAssertEqual(abs(earlyShift - early), 1, accuracy: 0.000_001)
            XCTAssertEqual(abs(lateShift - late), 1, accuracy: 0.000_001)
        }
    }

    func testAppendingReadingDoesNotRewriteHistoricalTrailingTrend() {
        let before = prepared()
        var readings = fixtureReadings
        readings.append(Reading(date: date("2026-07-18"), weightKg: UnitConvert.lbToKg(154), source: .manual))
        let after = prepared(readings: readings)
        XCTAssertEqual(Array(after.trailing7.prefix(before.trailing7.count)), before.trailing7)
    }

    func testEveryForecastStartsAtExactSharedAnchorAndTypicalIsUnshifted() {
        let model = prepared()
        for series in [model.bestForecast, model.typicalForecast, model.worstForecast] {
            XCTAssertEqual(series.first, model.forecastAnchor)
        }
        XCTAssertEqual(model.typicalForecast[1].value, 156.4, accuracy: 0.000_001)
    }

    func testPaceDeltaIsRequiredMinusTrendAndPositiveMeansAhead() {
        let model = prepared()
        let state = CutChartDomainState.resolved(for: model, calendar: calendar)
        let transformed = CutChartTransformer.transform(model, variation: .paceDelta, domains: state, calendar: calendar)
        XCTAssertEqual(transformed.trend.last!.value, 0.942_236, accuracy: 0.000_001)
        XCTAssertGreaterThan(transformed.trend.last!.value, 0)
    }

    func testCompletionPercentageUsesExactFormula() {
        let model = prepared()
        let state = CutChartDomainState.resolved(for: model, calendar: calendar)
        let transformed = CutChartTransformer.transform(model, variation: .completionPercent, domains: state, calendar: calendar)
        XCTAssertEqual(transformed.raw.last!.value, 74.693_878, accuracy: 0.000_001)
        XCTAssertEqual(transformed.trend.last!.value, 73.411_079, accuracy: 0.000_001)
    }

    func testRecentFocusAlwaysSpans44CalendarDaysAndTwelvePounds() {
        let model = prepared()
        let state = CutChartDomainState.resolved(for: model, calendar: calendar)
        let transformed = CutChartTransformer.transform(model, variation: .recentFocus, domains: state, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: transformed.xDomain.lowerBound, to: transformed.xDomain.upperBound).day, 44)
        XCTAssertEqual(transformed.yDomain.upperBound - transformed.yDomain.lowerBound, 12, accuracy: 0.000_001)

        let forced = CutChartDomainState(
            absoluteLower: state.absoluteLower,
            absoluteUpper: state.absoluteUpper,
            paceHalfRange: state.paceHalfRange,
            recentCenter: 170,
            recentSpan: 12
        )
        let translated = CutChartDomainState.resolved(for: model, previous: forced, calendar: calendar)
        XCTAssertLessThan(translated.recentCenter, forced.recentCenter)
        XCTAssertEqual(translated.recentSpan, forced.recentSpan)
    }

    private func transformedValue(
        weight: Double,
        date: Date,
        variation: CutChartVariation,
        model: CutChartModel
    ) -> Double {
        switch variation {
        case .fixedFullCut, .recentFocus:
            return weight
        case .remainingToGoal:
            return weight - model.targetWeightLb
        case .cumulativeLoss:
            return model.startWeightLb - weight
        case .paceDelta:
            return model.requiredPaceValue(at: date) - weight
        case .completionPercent:
            return 100 * (model.startWeightLb - weight) / (model.startWeightLb - model.targetWeightLb)
        }
    }
}
