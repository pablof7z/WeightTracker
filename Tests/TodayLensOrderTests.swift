#if DEBUG
import XCTest
import SwiftUI
@testable import WeightTracker

/// The Today carousel is driven entirely by two persisted strings, so the
/// decode path is the thing standing between a stale preference and an empty or
/// ill-typed pager.
final class TodayLensOrderTests: XCTestCase {

    // MARK: - Order decode / encode / normalize

    func testDefaultOrderIsEveryLens() {
        XCTAssertEqual(TodayLensOrder.default, TodayLens.allCases)
        XCTAssertEqual(TodayLens.allCases.count, 9)
    }

    func testDecodeDropsUnknownRawValuesAndBackfillsMissingOnes() {
        let decoded = TodayLensOrder.decode("pace,notALens,weeklyLoss,fixedFullCut")
        // Unknown values vanish; the known ones keep their stated order.
        XCTAssertEqual(Array(decoded.prefix(2)), [.pace, .weeklyLoss])
        // Everything else is backfilled in canonical order, exactly once.
        XCTAssertEqual(Set(decoded), Set(TodayLens.allCases))
        XCTAssertEqual(decoded.count, TodayLens.allCases.count)
    }

    func testDecodingGarbageStillYieldsTheFullDefaultOrder() {
        XCTAssertEqual(TodayLensOrder.decode(""), TodayLensOrder.default)
        XCTAssertEqual(TodayLensOrder.decode(",,,"), TodayLensOrder.default)
        XCTAssertEqual(TodayLensOrder.decode("totallyBogus"), TodayLensOrder.default)
    }

    func testNormalizedDeduplicates() {
        let normalized = TodayLensOrder.normalized([.pace, .pace, .forecast, .pace])
        XCTAssertEqual(Array(normalized.prefix(2)), [.pace, .forecast])
        XCTAssertEqual(normalized.count, TodayLens.allCases.count)
    }

    func testEncodeDecodeRoundTrip() {
        let custom: [TodayLens] = [.weeklyRange, .currentWeight, .weeklyLoss, .fullCut,
                                   .pace, .forecast, .thisWeek, .totalLost, .weeklyAverage]
        XCTAssertEqual(TodayLensOrder.decode(TodayLensOrder.encode(custom)), custom)
    }

    // MARK: - Hidden set

    func testHiddenRoundTripsAndIgnoresUnknownValues() {
        let hidden: Set<TodayLens> = [.forecast, .weeklyLoss]
        XCTAssertEqual(TodayLensOrder.decodeHidden(TodayLensOrder.encodeHidden(hidden)), hidden)
        XCTAssertEqual(TodayLensOrder.decodeHidden("forecast,junk"), [.forecast])
        XCTAssertTrue(TodayLensOrder.decodeHidden("").isEmpty)
    }

    /// The encoding must not depend on Set iteration order, or the stored
    /// string would churn on every write.
    func testHiddenEncodingIsCanonicallyOrdered() {
        let a = TodayLensOrder.encodeHidden([.weeklyLoss, .currentWeight])
        let b = TodayLensOrder.encodeHidden([.currentWeight, .weeklyLoss])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, "currentWeight,weeklyLoss")
    }

    // MARK: - Enabled set (what the carousel renders)

    func testEnabledHonoursBothOrderAndHiddenSet() {
        let order = TodayLensOrder.encode([.pace, .currentWeight, .weeklyRange])
        let hidden = TodayLensOrder.encodeHidden([.currentWeight])
        let enabled = TodayLensOrder.enabled(orderRaw: order, hiddenRaw: hidden)
        XCTAssertEqual(Array(enabled.prefix(2)), [.pace, .weeklyRange])
        XCTAssertFalse(enabled.contains(.currentWeight))
        XCTAssertEqual(enabled.count, TodayLens.allCases.count - 1)
    }

    /// The all-hidden fallback: disabling every lens must never produce an empty
    /// carousel.
    func testAllHiddenFallsBackToCurrentWeight() {
        let hidden = TodayLensOrder.encodeHidden(Set(TodayLens.allCases))
        let enabled = TodayLensOrder.enabled(orderRaw: "", hiddenRaw: hidden)
        XCTAssertEqual(enabled, [.currentWeight])
        XCTAssertEqual(TodayLensOrder.launchLens(in: enabled), .currentWeight)
    }

    func testLaunchLensPrefersCurrentWeightThenFirstEnabled() {
        XCTAssertEqual(TodayLensOrder.launchLens(in: [.pace, .currentWeight]), .currentWeight)
        XCTAssertEqual(TodayLensOrder.launchLens(in: [.pace, .forecast]), .pace)
        XCTAssertEqual(TodayLensOrder.launchLens(in: []), .currentWeight)
    }
}

// MARK: - The three restored lenses

@MainActor
final class RestoredLensTests: XCTestCase {

    /// Full Cut shows absolute weight over the *whole* plan timeline, so its
    /// hero is the latest reading and its x-domain is the cut itself.
    func testFullCutHeroAndDomain() throws {
        let builder = LensPreviewFixture.builder(.lbs)
        let chart = LensPreviewFixture.chart
        let rendered = builder.render(.fullCut)

        let latest = try XCTUnwrap(chart.raw.last).value
        XCTAssertEqual(rendered.heroValue, String(format: "%.1f", latest))
        XCTAssertEqual(rendered.plot.xDomain.lowerBound, chart.startDate)
        XCTAssertEqual(rendered.plot.xDomain.upperBound, chart.targetDate)
        // Raw line + trailing-7 trend, and a target reference line.
        XCTAssertEqual(rendered.plot.series.count, 2)
        XCTAssertEqual(rendered.plot.series.last?.points.count, chart.raw.count)
        XCTAssertEqual(rendered.plot.references.count, 1)
        XCTAssertEqual(rendered.stats.map(\.label), ["Start", "Lost", "Target"])
    }

    /// Weekly Range draws one whisker per plotted week, spanning that week's
    /// observed minimum to maximum, and the y-domain must contain them.
    func testWeeklyRangeWhiskersMatchWeeklyMinMax() throws {
        let builder = LensPreviewFixture.builder(.lbs)
        let weekly = LensPreviewFixture.weekly
        let rendered = builder.render(.weeklyRange)
        let visible = Array(weekly.points.suffix(9))

        XCTAssertEqual(rendered.plot.whiskers.count, visible.count)
        for (w, point) in zip(rendered.plot.whiskers, visible) {
            XCTAssertEqual(w.date, point.weekStart)
            XCTAssertEqual(w.low, point.minWeight, accuracy: 0.0001)
            XCTAssertEqual(w.high, point.maxWeight, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(w.low, w.high)
            XCTAssertTrue(rendered.plot.yDomain.contains(w.low))
            XCTAssertTrue(rendered.plot.yDomain.contains(w.high))
        }
        let current = try XCTUnwrap(visible.last)
        XCTAssertEqual(rendered.heroValue, String(format: "%.1f", current.averageWeight))
        XCTAssertEqual(rendered.stats.map(\.label), ["Range", "Previous", "Readings"])
    }

    /// Weekly Loss is bars from a zero baseline, one per comparable week, with
    /// the required weekly rate as a labeled reference.
    func testWeeklyLossBarsAndRequiredReference() throws {
        let builder = LensPreviewFixture.builder(.lbs)
        let weekly = LensPreviewFixture.weekly
        let rendered = builder.render(.weeklyLoss)

        let comparable = Array(weekly.points.filter { $0.lossVsPrevious != nil }.suffix(9))
        let barSet = try XCTUnwrap(rendered.plot.bars.first)
        XCTAssertEqual(barSet.baseline, 0)
        XCTAssertEqual(barSet.points.count, comparable.count)
        XCTAssertFalse(comparable.isEmpty, "fixture must produce comparable weeks")
        for (bar, point) in zip(barSet.points, comparable) {
            XCTAssertEqual(bar.date, point.weekStart)
            XCTAssertEqual(bar.value, try XCTUnwrap(point.lossVsPrevious), accuracy: 0.0001)
        }
        // Zero baseline plus the labeled required-rate line.
        XCTAssertEqual(rendered.plot.references.count, 2)
        XCTAssertEqual(rendered.plot.references.last?.label, "Required")
        // Bars are centered on their week, so the domain is padded rather than
        // clamped — otherwise the edge bars would be sliced in half.
        XCTAssertLessThan(rendered.plot.xDomain.lowerBound, try XCTUnwrap(barSet.points.first).date)
        XCTAssertGreaterThan(rendered.plot.xDomain.upperBound, try XCTUnwrap(barSet.points.last).date)

        let latestLoss = try XCTUnwrap(comparable.last?.lossVsPrevious)
        XCTAssertEqual(rendered.heroValue, String(format: "%+.1f", latestLoss))
        XCTAssertEqual(rendered.stats.map(\.label), ["Required", "Vs required", "Weeks"])
    }

    // MARK: - Per-lens daily photo assignment

    /// Each lens gets its own photo for the day, so the day's assignment must be
    /// a genuine permutation (no lens silently sharing another's slot when the
    /// collection is large enough).
    func testDailyPhotoShuffleIsAPermutation() {
        for count in [1, 3, 9, 20] {
            let order = DailyPhotoStore.shuffledIndices(count: count, seed: 12_345)
            XCTAssertEqual(order.count, count)
            XCTAssertEqual(Set(order), Set(0..<count), "count \(count) lost or duplicated an index")
        }
    }

    /// Same day → same assignment, so the backdrop never changes on redraw.
    func testDailyPhotoShuffleIsDeterministicForAGivenDay() {
        let a = DailyPhotoStore.shuffledIndices(count: 9, seed: 20_294)
        let b = DailyPhotoStore.shuffledIndices(count: 9, seed: 20_294)
        XCTAssertEqual(a, b)
    }

    /// A new day reshuffles, so the set of backdrops rotates over time.
    func testDailyPhotoShuffleChangesAcrossDays() {
        let today = DailyPhotoStore.shuffledIndices(count: 9, seed: 20_294)
        let laterDays = (1...7).map { DailyPhotoStore.shuffledIndices(count: 9, seed: 20_294 + UInt64($0)) }
        XCTAssertTrue(laterDays.contains { $0 != today }, "assignment never rotated across a week")
    }

    /// Every lens, new ones included, must carry a non-empty accessibility
    /// summary — the hero and metrics are the only data VoiceOver ever reads.
    func testAllNineLensesRenderWithAccessibilitySummaries() {
        let builder = LensPreviewFixture.builder(.lbs)
        for lens in TodayLens.allCases {
            let rendered = builder.render(lens)
            XCTAssertFalse(rendered.accessibilitySummary.isEmpty, "\(lens.rawValue)")
            XCTAssertFalse(rendered.heroValue.isEmpty, "\(lens.rawValue)")
            XCTAssertEqual(rendered.stats.count, 3, "\(lens.rawValue)")
            XCTAssertFalse(lens.detail.isEmpty, "\(lens.rawValue)")
        }
    }
}
#endif
