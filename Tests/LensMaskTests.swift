import XCTest
import SwiftUI
@testable import WeightTracker

/// The decorative background is revealed through `LensMask`'s vertical alpha
/// ramp. These assert the spec's shape: zero through the upper 30% (so the top
/// is pure system background), ~0.5 at the midpoint, strongest toward the
/// bottom, and monotonic throughout — plus that the gradient stops driving the
/// `Canvas` mask are generated from the same anchors.
final class LensMaskTests: XCTestCase {
    func testTopThirtyPercentIsSystemBackground() {
        // Everything through the upper ~30% reveals nothing, so the viewer sees
        // pure system background there in both light and dark.
        for t in stride(from: 0.0, through: 0.30, by: 0.02) {
            XCTAssertEqual(LensMask.baseAlpha(normalizedY: t), 0, accuracy: 1e-9,
                           "expected 0 reveal at t=\(t)")
        }
    }

    func testMidpointAnchor() {
        XCTAssertEqual(LensMask.baseAlpha(normalizedY: 0.50), 0.50, accuracy: 1e-9)
    }

    func testBottomIsStrong() {
        let bottom = LensMask.baseAlpha(normalizedY: 1.0)
        XCTAssertEqual(bottom, 0.85, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(bottom, 0.80)
        XCTAssertLessThanOrEqual(bottom, 0.90)
        // Strictly stronger than the midpoint.
        XCTAssertGreaterThan(bottom, LensMask.baseAlpha(normalizedY: 0.50))
    }

    func testMonotonicNonDecreasing() {
        var previous = -1.0
        for i in 0...200 {
            let t = Double(i) / 200.0
            let a = LensMask.baseAlpha(normalizedY: t)
            XCTAssertGreaterThanOrEqual(a, previous - 1e-12, "reveal dipped at t=\(t)")
            previous = a
        }
    }

    func testStrictlyIncreasingBelowThreshold() {
        // Below the plotted-curve region the reveal must genuinely climb, not
        // plateau, between the threshold and the bottom.
        let a = LensMask.baseAlpha(normalizedY: 0.40)
        let b = LensMask.baseAlpha(normalizedY: 0.70)
        let c = LensMask.baseAlpha(normalizedY: 0.95)
        XCTAssertGreaterThan(a, 0)
        XCTAssertGreaterThan(b, a)
        XCTAssertGreaterThan(c, b)
    }

    func testClamping() {
        XCTAssertEqual(LensMask.baseAlpha(normalizedY: -0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(LensMask.baseAlpha(normalizedY: 1.5), 0.85, accuracy: 1e-9)
    }

    func testAboveCurveCapIsFaint() {
        XCTAssertEqual(LensMask.aboveCurveCap, 0.10, accuracy: 1e-9)
        // The cap is far below the midpoint reveal, so above the curve the
        // decorative layer stays faint no matter how strong the ramp is there.
        XCTAssertLessThan(LensMask.aboveCurveCap, LensMask.baseAlpha(normalizedY: 0.50))
    }

    func testCappedRampIsATrueCeiling() {
        // The cap is reached exactly where baseAlpha == aboveCurveCap, and the
        // capped ramp equals min(base, cap): it tracks the base ramp up to the
        // cap, then plateaus — so it fades to 0 through the top (no seam) yet
        // never exceeds the cap.
        XCTAssertEqual(LensMask.baseAlpha(normalizedY: LensMask.cappedAt),
                       LensMask.aboveCurveCap, accuracy: 1e-9)
        let stops = LensMask.cappedRampStops
        XCTAssertEqual(stops.count, 4)
        XCTAssertEqual(stops[0].location, 0, accuracy: 1e-9)
        XCTAssertEqual(stops[1].location, LensMask.systemBackgroundTop, accuracy: 1e-9)
        XCTAssertEqual(stops[2].location, LensMask.cappedAt, accuracy: 1e-9)
        XCTAssertEqual(stops[3].location, 1.0, accuracy: 1e-9)
        // Plateaus at the cap through the bottom.
        for stop in stops {
            let alpha = stop.color.resolve(in: EnvironmentValues()).opacity
            XCTAssertLessThanOrEqual(Double(alpha), LensMask.aboveCurveCap + 1e-6)
        }
    }

    func testRampStopsMatchAnchors() {
        let stops = LensMask.rampStops
        XCTAssertEqual(stops.count, 4)
        XCTAssertEqual(stops[0].location, 0, accuracy: 1e-9)
        XCTAssertEqual(stops[1].location, LensMask.systemBackgroundTop, accuracy: 1e-9)
        XCTAssertEqual(stops[2].location, LensMask.midpoint, accuracy: 1e-9)
        XCTAssertEqual(stops[3].location, 1.0, accuracy: 1e-9)
    }
}
