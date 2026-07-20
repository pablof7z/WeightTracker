import SwiftUI
import UIKit

// MARK: - Color mixing

extension Color {
    /// Linear RGB blend toward `other` by `amount` (0…1). Used to derive the
    /// per-lens atmospheric depth gradient from a single categorical accent.
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

// MARK: - Per-lens atmospheric depth gradient

extension TodayLens {
    /// Shared deep anchor so every lens bottom reads as the same immersive
    /// navy family, differentiated only by the accent tint mixed into it.
    static let depthNavy = Color(red: 0.055, green: 0.075, blue: 0.145)

    /// Top→bottom depth stops for the full-canvas background. Top is a very pale
    /// wash of the accent (in light) or a soft dark tint (in dark); it deepens
    /// through a medium accent into a near-navy floor. Scheme-aware so the seam
    /// under the hero stays soft in both appearances.
    func depthStops(for scheme: ColorScheme) -> [Color] {
        let base = accent
        if scheme == .dark {
            return [
                base.mixed(with: Self.depthNavy, amount: 0.58),
                base.mixed(with: Self.depthNavy, amount: 0.74),
                base.mixed(with: Self.depthNavy, amount: 0.92),
            ]
        } else {
            return [
                base.mixed(with: .white, amount: 0.60),
                base.mixed(with: Self.depthNavy, amount: 0.34),
                base.mixed(with: Self.depthNavy, amount: 0.80),
            ]
        }
    }
}

// MARK: - Continuous canvas background

/// The single background layer behind the entire lower visualization: an
/// atmospheric depth gradient by default, or an optional daily photo backdrop
/// (aspect-fill + accent monochrome overlay + bottom vignette) when enabled.
/// It bleeds to the bottom safe-area edge and sits behind the chart, metrics,
/// and page dots so there is never a white gap.
struct LensCanvasBackground: View {
    let lens: TodayLens
    var photo: UIImage? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    // Monochrome accent wash to unify the photo with the lens.
                    // Held high deliberately: the photograph is atmosphere, not
                    // content, so it stays recognizable through the center while
                    // the data keeps visual primacy.
                    lens.accent
                        .blendMode(.color)
                        .opacity(0.78)
                    // Soft light scrim at the top (behind the hero seam) and a
                    // darker bottom vignette so dates + metrics stay legible.
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.black.opacity(0.18), location: 0.0),
                            .init(color: Color.black.opacity(0.08), location: 0.30),
                            .init(color: Color.black.opacity(0.40), location: 0.72),
                            .init(color: Color.black.opacity(0.74), location: 1.0),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    // Keep the accent alive underneath as a faint tint floor.
                    LinearGradient(
                        colors: [.clear, lens.accent.mixed(with: TodayLens.depthNavy, amount: 0.6).opacity(0.48)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    LinearGradient(
                        gradient: Gradient(colors: lens.depthStops(for: scheme)),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
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
