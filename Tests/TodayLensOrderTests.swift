#if DEBUG
import XCTest
import SwiftUI
@testable import WeightTracker

final class TodayLensOrderTests: XCTestCase {
    func testDefaultIsTheThreeDistinctDecisionViews() {
        XCTAssertEqual(TodayLensOrder.default, [.progress, .recentTrend, .weeklySummary])
        XCTAssertEqual(TodayLens.allCases.count, 3)
    }

    func testLegacyNineLensPreferenceMigratesToCanonicalOrder() {
        XCTAssertEqual(
            TodayLensOrder.decode("currentWeight,pace,forecast,weeklyLoss"),
            TodayLensOrder.default
        )
    }

    func testOrderHiddenAndFallbackRemainStable() {
        let order = TodayLensOrder.encode([.recentTrend, .progress, .weeklySummary])
        XCTAssertEqual(TodayLensOrder.decode(order), [.recentTrend, .progress, .weeklySummary])
        let hidden = TodayLensOrder.encodeHidden([.progress])
        XCTAssertEqual(TodayLensOrder.enabled(orderRaw: order, hiddenRaw: hidden), [.recentTrend, .weeklySummary])
        let allHidden = TodayLensOrder.encodeHidden(Set(TodayLens.allCases))
        XCTAssertEqual(TodayLensOrder.enabled(orderRaw: order, hiddenRaw: allHidden), [.progress])
        XCTAssertEqual(TodayLensOrder.launchLens(in: [.recentTrend, .weeklySummary]), .recentTrend)
    }
}

@MainActor
final class TodayLensRenderingTests: XCTestCase {
    func testAllThreeLensesHaveScaleStraightGeometryStatsAndScrub() throws {
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

    func testWeeklySummaryOwnsMeansRangesAndCoverageTogether() {
        let rendered = LensPreviewFixture.builder(.lbs).render(.weeklySummary)
        let visible = Array(LensPreviewFixture.weekly.points.suffix(9))
        XCTAssertEqual(rendered.plot.whiskers.count, visible.count)
        XCTAssertEqual(rendered.stats.map(\.label).first, "Observed range")
    }
}
#endif
