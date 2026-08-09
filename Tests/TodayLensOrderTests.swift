#if DEBUG
import XCTest
import SwiftUI
@testable import WeightTracker

final class TodayLensOrderTests: XCTestCase {
    func testDefaultRestoresTheFullChartCollection() {
        XCTAssertEqual(
            TodayLensOrder.default,
            [.progress, .currentWeight, .totalLost, .thisWeek, .weeklyAverage,
             .recentTrend, .pace, .forecast, .fullCut, .weeklyRange, .weeklyLoss]
        )
        XCTAssertEqual(TodayLens.allCases.count, 11)
    }

    func testLegacyPreferencesRestoreTheirChartsAndMigrateWeeklySummary() {
        XCTAssertEqual(
            TodayLensOrder.decode("currentWeight,pace,forecast,weeklyLoss"),
            [.currentWeight, .pace, .forecast, .weeklyLoss, .progress, .totalLost,
             .thisWeek, .weeklyAverage, .recentTrend, .fullCut, .weeklyRange]
        )
        XCTAssertEqual(TodayLensOrder.decode("progress,weeklySummary").prefix(2), [.progress, .weeklyAverage])
    }

    func testOrderHiddenAndFallbackRemainStable() {
        let order = TodayLensOrder.encode([.recentTrend, .progress, .weeklyAverage])
        XCTAssertEqual(TodayLensOrder.decode(order).prefix(3), [.recentTrend, .progress, .weeklyAverage])
        let hidden = TodayLensOrder.encodeHidden([.progress])
        XCTAssertEqual(TodayLensOrder.enabled(orderRaw: order, hiddenRaw: hidden).first, .recentTrend)
        let allHidden = TodayLensOrder.encodeHidden(Set(TodayLens.allCases))
        XCTAssertEqual(TodayLensOrder.enabled(orderRaw: order, hiddenRaw: allHidden), [.progress])
        XCTAssertEqual(TodayLensOrder.launchLens(in: [.recentTrend, .weeklyAverage]), .recentTrend)
    }
}

@MainActor
final class TodayLensRenderingTests: XCTestCase {
    func testEveryLensHasStraightGeometryStatsScrubAndInitialValueLabel() throws {
        let builder = LensPreviewFixture.builder(.lbs)
        for lens in TodayLens.allCases {
            let rendered = builder.render(lens)
            XCTAssertFalse(rendered.accessibilitySummary.isEmpty)
            XCTAssertEqual(rendered.stats.count, 3)
            XCTAssertGreaterThanOrEqual(rendered.plot.references.filter {
                if case .horizontal = $0.kind { return true }
                return false
            }.count, 3)
            XCTAssertTrue(rendered.plot.series.allSatisfy { !$0.smooth })
            XCTAssertTrue(rendered.plot.bands.allSatisfy { !$0.smooth })
            XCTAssertFalse(try XCTUnwrap(rendered.scrub).points.isEmpty)
            XCTAssertEqual(rendered.plot.pointLabels.count, 1, "\(lens.rawValue) needs its first value label")
            XCTAssertFalse(rendered.heroContext?.localizedCaseInsensitiveContains("readings") ?? false)
        }
    }

    func testProgressPlotsRawPointsTrendPlanAndOptionalForecast() {
        let rendered = LensPreviewFixture.builder(.lbs).render(.progress)
        XCTAssertEqual(rendered.plot.markerSets.first?.points.count, LensPreviewFixture.analytics.observations.count)
        XCTAssertGreaterThanOrEqual(rendered.plot.series.count, 2)
        XCTAssertEqual(rendered.stats.map(\.label).prefix(2), ["Latest", "Plan today"])
    }

    func testRecentTrendDoesNotPlotHistoricalRollingPaceCurve() {
        let rendered = LensPreviewFixture.builder(.lbs).render(.recentTrend)
        XCTAssertLessThanOrEqual(rendered.plot.series.count, 2)
        XCTAssertEqual(rendered.stats.map(\.label), ["Needed now", "Original plan", "Current trend"])
    }

    func testWeekToDateAverageOwnsMeansAndObservedRanges() {
        let rendered = LensPreviewFixture.builder(.lbs).render(.weeklyAverage)
        let visible = Array(LensPreviewFixture.weekly.points.suffix(9))
        XCTAssertEqual(rendered.plot.whiskers.count, visible.count)
        XCTAssertEqual(rendered.stats.map(\.label).first, "Observed range")
        XCTAssertTrue(rendered.heroContext?.contains("WTD") == true)
    }

    func testWeekOverWeekUsesSignedMeanChangeBars() throws {
        let rendered = LensPreviewFixture.builder(.lbs).render(.weeklyLoss)
        let bars = try XCTUnwrap(rendered.plot.bars.first).points
        XCTAssertFalse(bars.isEmpty)
        XCTAssertEqual(rendered.plot.series.count, 0)
        XCTAssertEqual(Array(rendered.stats.map(\.label).suffix(2)), ["Current mean", "Planned change"])
    }
}
#endif
