#if DEBUG
import XCTest
import SwiftUI
@testable import WeightTracker

/// Renders every lens to a PNG via `ImageRenderer` and writes them into
/// `docs/today-lenses/` so the repository always carries fresh artifacts. Skips
/// gracefully when the host docs directory is not writable from the simulator.
@MainActor
final class TodayLensSnapshotTests: XCTestCase {
    func testExportLensSnapshots() throws {
        let outDir = URL(fileURLWithPath: "/Users/pablofernandez/Work/cut-tracker/docs/today-lenses", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let probe = outDir.appendingPathComponent(".probe")
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
        } catch {
            throw XCTSkip("host docs dir not writable from simulator: \(error)")
        }

        let combos: [(TodayLens, WeightUnit, ColorScheme)] = TodayLens.allCases.flatMap { lens in
            [(lens, WeightUnit.lbs, ColorScheme.light), (lens, WeightUnit.kg, ColorScheme.dark)]
        }
        for (lens, unit, scheme) in combos {
            let view = makeLensSnapshotView(lens, unit: unit)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            guard let image = renderer.uiImage, let data = image.pngData() else {
                XCTFail("render failed for \(lens.rawValue)")
                continue
            }
            let suffix = scheme == .dark ? "dark" : "light"
            let name = "\(lens.rawValue)-\(unit.rawValue)-\(suffix).png"
            try data.write(to: outDir.appendingPathComponent(name))
        }
    }
}
#endif
