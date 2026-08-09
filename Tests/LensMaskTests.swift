import XCTest
import SwiftUI
@testable import WeightTracker

/// The decorative background is revealed through `LensMask`'s vertical alpha
/// ramp. These assert the spec's shape: a stable faint floor through the upper
/// part (the top of the app never fades to nothing — it holds the same faint
/// value used above the plotted curve), ~0.5 at the midpoint, strongest toward
/// the bottom, and monotonic throughout — plus that the gradient stops driving
/// the `Canvas` mask are generated from the same anchors.
final class LensMaskTests: XCTestCase {
    func testTopHoldsStableFaintFloor() {
        // Everything through the upper part holds the faint floor (== the
        // above-curve value), never fading to 0, so the top of the app is stable
        // and matches the region above the chart line.
        for t in stride(from: 0.0, through: 0.30, by: 0.02) {
            XCTAssertEqual(LensMask.baseAlpha(normalizedY: t), LensMask.aboveCurveCap,
                           accuracy: 1e-9, "expected stable floor at t=\(t)")
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
        XCTAssertEqual(LensMask.baseAlpha(normalizedY: -0.5), LensMask.aboveCurveCap, accuracy: 1e-9)
        XCTAssertEqual(LensMask.baseAlpha(normalizedY: 1.5), 0.85, accuracy: 1e-9)
    }

    func testAboveCurveCapIsFaint() {
        XCTAssertEqual(LensMask.aboveCurveCap, 0.10, accuracy: 1e-9)
        // The cap is far below the midpoint reveal, so above the curve the
        // decorative layer stays faint no matter how strong the ramp is there.
        XCTAssertLessThan(LensMask.aboveCurveCap, LensMask.baseAlpha(normalizedY: 0.50))
    }

    func testFloorHoldsThenClimbs() {
        // Below the floor threshold the reveal is flat at the faint floor; the
        // stop that ends the floor sits at the threshold and carries that value.
        XCTAssertEqual(LensMask.baseAlpha(normalizedY: LensMask.floorThreshold),
                       LensMask.aboveCurveCap, accuracy: 1e-9)
        XCTAssertGreaterThan(LensMask.baseAlpha(normalizedY: LensMask.floorThreshold + 0.05),
                             LensMask.aboveCurveCap)
    }

    func testRampStopsMatchAnchors() {
        let stops = LensMask.rampStops
        XCTAssertEqual(stops.count, 4)
        XCTAssertEqual(stops[0].location, 0, accuracy: 1e-9)
        XCTAssertEqual(stops[1].location, LensMask.floorThreshold, accuracy: 1e-9)
        XCTAssertEqual(stops[2].location, LensMask.midpoint, accuracy: 1e-9)
        XCTAssertEqual(stops[3].location, 1.0, accuracy: 1e-9)
        // First two stops carry the faint floor, not transparency.
        let floorAlpha = stops[0].color.resolve(in: EnvironmentValues()).opacity
        XCTAssertEqual(Double(floorAlpha), LensMask.aboveCurveCap, accuracy: 1e-6)
    }
}
