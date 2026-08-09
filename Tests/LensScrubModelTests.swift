#if DEBUG
import XCTest
import SwiftUI
@testable import WeightTracker

/// The scrub feature indexes three parallel arrays (`points`, `info`,
/// `callouts`) with a single hovered index derived from hit-testing, so their
/// lengths agreeing is the invariant the renderer and hero both depend on.
@MainActor
final class LensScrubModelTests: XCTestCase {
    func testEveryLensExposesAConsistentScrubModel() throws {
        let builder = LensPreviewFixture.builder(.lbs)
        for lens in TodayLens.allCases {
            let rendered = builder.render(lens)
            let scrub = try XCTUnwrap(rendered.scrub, "\(lens.rawValue) has no scrub model")
            XCTAssertFalse(scrub.points.isEmpty, "\(lens.rawValue) has no inspectable points")
            XCTAssertEqual(scrub.info.count, scrub.points.count, "\(lens.rawValue) info/points mismatch")
            XCTAssertEqual(scrub.callouts.count, scrub.points.count, "\(lens.rawValue) callouts/points mismatch")
            // Points must be ordered so nearest-x hit testing is meaningful.
            XCTAssertEqual(scrub.points.map(\.date), scrub.points.map(\.date).sorted(), "\(lens.rawValue) points are not chronological")
            // Out-of-range lookups must be nil rather than trapping.
            XCTAssertNil(scrub.info(at: -1))
            XCTAssertNil(scrub.info(at: scrub.points.count))
            for i in scrub.points.indices {
                XCTAssertFalse(try XCTUnwrap(scrub.info(at: i)).heroValue.isEmpty)
            }
        }
    }

    /// Scrub readouts are built in the display unit, so switching units must
    /// change the rendered value strings rather than silently reusing pounds.
    func testScrubValuesFollowTheDisplayUnit() throws {
        let lbs = try XCTUnwrap(LensPreviewFixture.builder(.lbs).render(.progress).scrub)
        let kg = try XCTUnwrap(LensPreviewFixture.builder(.kg).render(.progress).scrub)
        XCTAssertEqual(lbs.points.count, kg.points.count)
        let i = lbs.points.count / 2
        XCTAssertNotEqual(lbs.info[i].heroValue, kg.info[i].heroValue)
        XCTAssertEqual(lbs.info[i].heroUnit, "lb")
        XCTAssertEqual(kg.info[i].heroUnit, "kg")
    }
}
#endif
