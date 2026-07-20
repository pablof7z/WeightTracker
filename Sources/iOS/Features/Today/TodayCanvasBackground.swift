import SwiftUI
import UIKit

// MARK: - Color mixing

extension Color {
    /// Linear RGB blend toward `other` by `amount` (0…1). Used to derive the
    /// per-lens decorative gradient from a single categorical accent.
    func mixed(with other: Color, amount: Double) -> Color {
        let a = UIColor(self)
        let b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(max(0, min(1, amount)))
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t)
        )
    }
}

// MARK: - Decorative palette

extension TodayLens {
    /// Shared deep anchor so every lens floor reads as the same immersive navy
    /// family, differentiated only by the accent tint mixed into it. The mask —
    /// not this color — is what fades the decorative layer to the semantic
    /// system background toward the top, so this content is scheme-independent.
    static let depthNavy = Color(red: 0.055, green: 0.075, blue: 0.145)

    /// Top→bottom colors for the accent decorative layer (photo mode off). It is
    /// only ever seen through the alpha mask, which keeps it near-absent at the
    /// top and reveals it toward the bottom, so the floor deepens into navy to
    /// keep the light supporting figures legible in both appearances.
    /// Deterministic and independent of appearance by design.
    var decorativeColors: [Color] {
        [
            accent.mixed(with: .white, amount: 0.06),
            accent,
            accent.mixed(with: Self.depthNavy, amount: 0.80),
        ]
    }

    /// Fixed source-over tint laid over a daily photo so it reads as quiet
    /// atmosphere unified with the lens — deterministic, applied at a constant
    /// opacity regardless of the photograph's luminance (no blend mode).
    var photoTintOpacity: Double { 0.60 }
}

// MARK: - Base decorative alpha mask

/// The vertical alpha field the decorative background is revealed through, plus
/// the flat cap used above the plotted curve. Extracted as pure math so the
/// ramp is unit-testable and the gradient stops that drive the `Canvas` mask are
/// generated from the same anchors the tests assert.
///
/// `t` is the normalized vertical position over the whole page: 0 at the top,
/// 1 at the bottom. The decorative layer is essentially absent through the upper
/// ~30% (so the top is literally the system background), climbs through the
/// middle to ~0.5 at the vertical midpoint, and is strongest toward the bottom.
enum LensMask {
    /// Top of the page stays pure system background up to here.
    static let systemBackgroundTop: Double = 0.30
    /// Vertical midpoint reveal.
    static let midpoint: Double = 0.50
    static let midpointAlpha: Double = 0.50
    /// Reveal at the very bottom of the page.
    static let bottomAlpha: Double = 0.85
    /// Decorative opacity is capped to this flat value above the plotted curve,
    /// no matter how strong the base ramp is there.
    static let aboveCurveCap: Double = 0.10

    /// Piecewise-linear base reveal. Monotonic non-decreasing in `t`.
    static func baseAlpha(normalizedY t: Double) -> Double {
        let y = min(1, max(0, t))
        if y <= systemBackgroundTop { return 0 }
        if y <= midpoint {
            let f = (y - systemBackgroundTop) / (midpoint - systemBackgroundTop)
            return f * midpointAlpha
        }
        let f = (y - midpoint) / (1.0 - midpoint)
        return midpointAlpha + f * (bottomAlpha - midpointAlpha)
    }

    /// The gradient stops that reproduce `baseAlpha` exactly inside a `Canvas`
    /// alpha mask (white opacity == alpha). Because the anchors are shared with
    /// `baseAlpha`, the drawn ramp and the tested math cannot diverge.
    static var rampStops: [Gradient.Stop] {
        [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(0), location: systemBackgroundTop),
            .init(color: .white.opacity(midpointAlpha), location: midpoint),
            .init(color: .white.opacity(bottomAlpha), location: 1.0),
        ]
    }

    /// The normalized vertical position at which `baseAlpha` first reaches the
    /// above-curve cap, i.e. `baseAlpha(cappedAt) == aboveCurveCap`.
    static var cappedAt: Double {
        systemBackgroundTop + (aboveCurveCap / midpointAlpha) * (midpoint - systemBackgroundTop)
    }

    /// Gradient stops for the reveal ABOVE the plotted curve: `min(baseAlpha, cap)`.
    /// It follows the base ramp until it hits the cap and then plateaus, so it is
    /// a true ceiling — the decorative layer stays faint above the curve AND
    /// still fades to nothing through the top (no hard seam against the system
    /// background). Shared anchors keep it consistent with `baseAlpha`.
    static var cappedRampStops: [Gradient.Stop] {
        [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(0), location: systemBackgroundTop),
            .init(color: .white.opacity(aboveCurveCap), location: cappedAt),
            .init(color: .white.opacity(aboveCurveCap), location: 1.0),
        ]
    }
}

// MARK: - Daily photo backdrop store

/// Persists a small collection of user-chosen photos (copied into Application
/// Support) and vends a deterministic once-per-day image so the backdrop is
/// stable across redraws and identical across all six lenses on a given day.
/// The atmospheric gradient is always the robust default; this is purely
/// additive and fully separable — when disabled or empty it vends `nil`.
@MainActor
final class DailyPhotoStore: ObservableObject {
    static let shared = DailyPhotoStore()

    @Published private(set) var filenames: [String] = []
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: AppPrefKey.todayPhotoEnabled) }
    }

    private let dir: URL
    private let defaults = UserDefaults.standard

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("TodayPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        enabled = defaults.bool(forKey: AppPrefKey.todayPhotoEnabled)
        filenames = (defaults.array(forKey: AppPrefKey.todayPhotoFiles) as? [String]) ?? []
    }

    var count: Int { filenames.count }

    func url(for name: String) -> URL { dir.appendingPathComponent(name) }

    /// Copies raw image data into the store under a stable filename.
    func addImageData(_ data: Data) {
        let name = UUID().uuidString + ".jpg"
        let target = dir.appendingPathComponent(name)
        do {
            try data.write(to: target, options: .atomic)
            filenames.append(name)
            persist()
        } catch {
            // A single failed import must never corrupt the collection.
        }
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
        filenames.removeAll { $0 == name }
        imageCache[name] = nil
        persist()
    }

    func removeAll() {
        for name in filenames { try? FileManager.default.removeItem(at: url(for: name)) }
        filenames = []
        imageCache.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(filenames, forKey: AppPrefKey.todayPhotoFiles)
    }

    /// Deterministic image for one lens on one day. Each lens gets its OWN photo
    /// so swiping between lenses changes the backdrop, and the whole assignment
    /// reshuffles once per day. Because the day's shuffle is a permutation,
    /// distinct lenses get distinct photos whenever the collection is at least
    /// as large as the lens count. Stable across redraws and relaunches.
    /// Returns `nil` unless enabled with photos.
    func dailyImage(
        for lens: TodayLens,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> UIImage? {
        guard enabled, !filenames.isEmpty else { return nil }
        let dayIndex = Int(calendar.startOfDay(for: date).timeIntervalSince1970 / 86_400)
        let order = Self.shuffledIndices(count: filenames.count, seed: UInt64(bitPattern: Int64(dayIndex)))
        let lensIndex = TodayLens.allCases.firstIndex(of: lens) ?? 0
        return image(named: filenames[order[lensIndex % order.count]])
    }

    /// Decoded-image cache so a body pass never re-reads a JPEG from disk.
    private var imageCache: [String: UIImage] = [:]

    private func image(named name: String) -> UIImage? {
        if let cached = imageCache[name] { return cached }
        guard let decoded = UIImage(contentsOfFile: url(for: name).path) else { return nil }
        imageCache[name] = decoded
        return decoded
    }

    /// Deterministic Fisher–Yates driven by SplitMix64. Same seed → same
    /// permutation, so the day's lens→photo assignment is fixed, and a new day
    /// index reshuffles everything.
    static func shuffledIndices(count: Int, seed: UInt64) -> [Int] {
        var indices = Array(0..<count)
        guard count > 1 else { return indices }
        var state = seed &* 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        for i in stride(from: count - 1, to: 0, by: -1) {
            indices.swapAt(i, Int(next() % UInt64(i + 1)))
        }
        return indices
    }
}
