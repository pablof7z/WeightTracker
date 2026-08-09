import SwiftUI
import UIKit

// MARK: - Plot spec

/// A declarative description of one full-bleed Today lens chart. Every visible
/// line is generated from the same points with the same interpolation as the
/// decorative mask boundary, so the reveal edge can never diverge from the line.
struct LensPlotSpec {
    var xDomain: ClosedRange<Date>
    var yDomain: ClosedRange<Double>
    var bands: [Band] = []
    var references: [Reference] = []
    var bars: [BarSet] = []
    var whiskers: [Whisker] = []
    var markerSets: [MarkerSet] = []
    var series: [Series] = []
    var endpoint: Endpoint?
    var pointLabels: [PointLabel] = []
    var dateLabels: [DateLabel] = []

    /// The lens's primary line, expressed in exactly the same points/domain the
    /// primary `Series` draws with. The decorative background is revealed below
    /// this curve and capped above it. `nil` for lenses without a single
    /// meaningful boundary (e.g. the weekly-loss bars) — those fall back to the
    /// base vertical ramp with no curve modulation.
    var maskBoundary: [DatedValue]? = nil
    var maskBoundarySmooth: Bool = false

    struct Series: Identifiable {
        let id = UUID()
        var points: [DatedValue]
        var color: Color
        var lineWidth: CGFloat = 2.6
        var dash: [CGFloat]?
        var smooth: Bool = false
        var opacity: Double = 1
        /// Optional dark halo stroked underneath the line so a white primary
        /// series stays legible over both the pale top and the navy floor of
        /// the decorative background.
        var haloColor: Color? = nil
    }

    /// Area between two lines (forecast lower/upper). Zero-width at the anchor,
    /// widening into the future by construction.
    struct Band {
        var lower: [DatedValue]
        var upper: [DatedValue]
        var color: Color
        var opacity: Double = 0.13
        var smooth: Bool = false
    }

    struct Reference: Identifiable {
        let id = UUID()
        enum Kind { case horizontal(Double), vertical(Date) }
        var kind: Kind
        var color: Color
        var dash: [CGFloat]? = [2, 4]
        var lineWidth: CGFloat = 1
        var label: String?
        var labelColor: Color = .secondary
    }

    /// Discrete columns drawn from a shared baseline value — the categorical
    /// counterpart to `Series`. Each point's value is the bar's far end, so a
    /// negative value simply grows downward from the baseline. Width is in
    /// points because the renderer, not the data, owns the pixel geometry.
    struct BarSet {
        var points: [DatedValue]
        var baseline: Double
        var color: Color
        var width: CGFloat = 16
        var opacity: Double = 0.9
        var cornerRadius: CGFloat = 2
    }

    /// A single vertical low→high segment at one date with subtle end caps —
    /// the per-point range primitive (weekly min/max). Drawn beneath the series
    /// so a line through the same dates stays dominant.
    struct Whisker: Identifiable {
        let id = UUID()
        var date: Date
        var low: Double
        var high: Double
        var color: Color
        var lineWidth: CGFloat = 1.4
        /// Full width of the little horizontal cap at each end, in points.
        var capWidth: CGFloat = 7
    }

    struct MarkerSet {
        var points: [DatedValue]
        var color: Color
        var radius: CGFloat = 2.4
        var hollow: Bool = false
    }

    /// A single restrained, outlined "current" point.
    struct Endpoint {
        var point: DatedValue
        var color: Color
        var radius: CGFloat = 5
        var haloColor: Color = .clear
    }

    struct DateLabel: Identifiable {
        let id = UUID()
        var date: Date
        var text: String
        var color: Color = .secondary
    }

    /// A compact value annotation attached to a real plotted point. The first
    /// point labels use a small positive x offset so they remain inside the
    /// chart while preserving the point's exact y position.
    struct PointLabel: Identifiable {
        let id = UUID()
        var point: DatedValue
        var text: String
        var color: Color = .secondary
        var xOffset: CGFloat = 7
    }
}

// MARK: - Shared geometry (line ⇄ mask boundary)

/// The data→plot coordinate mapping. One instance is shared by the decorative
/// mask boundary, the chart stroke, and the scrub hit-test so all three place
/// points identically.
struct LensPlotMap {
    let x: ClosedRange<Date>
    let y: ClosedRange<Double>
    let rect: CGRect

    func point(_ dv: DatedValue) -> CGPoint { CGPoint(x: px(dv.date), y: py(dv.value)) }
    func px(_ date: Date) -> CGFloat {
        let span = x.upperBound.timeIntervalSince(x.lowerBound)
        guard span > 0 else { return rect.minX }
        let t = date.timeIntervalSince(x.lowerBound) / span
        return rect.minX + CGFloat(t) * rect.width
    }
    func py(_ value: Double) -> CGFloat {
        let span = y.upperBound - y.lowerBound
        guard span > 0 else { return rect.midY }
        let t = (value - y.lowerBound) / span
        return rect.maxY - CGFloat(t) * rect.height
    }
}

/// Internal data insets (points), matching the historical `LensPlot` values so
/// the chart still reaches the edges. Leading is 0 (the line reaches the very
/// left edge); the right keeps a hair of room for the endpoint ring; top/bottom
/// are tight so the curve fills the plot rather than floating.
enum LensPlotInsets {
    static let leading: CGFloat = 0
    static let trailing: CGFloat = 7
    static let top: CGFloat = 8
    static let bottom: CGFloat = 14
}

/// The actual plot drawing rect: the measured chart slot inset by the data
/// insets. Shared by the backdrop renderer and the scrub hit-test.
func lensChartInner(_ slot: CGRect) -> CGRect {
    CGRect(
        x: slot.minX + LensPlotInsets.leading,
        y: slot.minY + LensPlotInsets.top,
        width: max(1, slot.width - LensPlotInsets.leading - LensPlotInsets.trailing),
        height: max(1, slot.height - LensPlotInsets.top - LensPlotInsets.bottom)
    )
}

/// One generator for every line and every mask boundary. Catmull-Rom when
/// smoothing, straight segments otherwise. Because the mask re-invokes this with
/// the identical points, the boundary geometry is guaranteed to match the line.
func lensLinePath(_ points: [CGPoint], smooth: Bool) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    lensAppendSegments(to: &path, points: points, smooth: smooth)
    return path
}

/// Appends the segments for `points` to `path`, continuing from its current
/// point (no `move`). Catmull-Rom when smoothing, straight otherwise.
func lensAppendSegments(to path: inout Path, points: [CGPoint], smooth: Bool) {
    guard points.count > 1 else { return }
    if !smooth {
        for p in points.dropFirst() { path.addLine(to: p) }
        return
    }
    for i in 0..<(points.count - 1) {
        let p0 = points[max(0, i - 1)]
        let p1 = points[i]
        let p2 = points[i + 1]
        let p3 = points[min(points.count - 1, i + 2)]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0, y: p1.y + (p2.y - p0.y) / 6.0)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0, y: p2.y - (p3.y - p1.y) / 6.0)
        path.addCurve(to: p2, control1: c1, control2: c2)
    }
}

// MARK: - The unified backdrop + chart renderer

/// One `Canvas` spanning the whole lens page. It draws, in order:
///   1. the semantic system background (opaque base),
///   2. a decorative layer (the day's photo, or an accent gradient) revealed
///      ONLY through an alpha mask — a page-height vertical ramp, capped to a
///      faint flat value above the plotted curve and left at the strong ramp
///      value below it,
///   3. the chart marks (references, bars, whiskers, markers, the primary line,
///      endpoint, labels, scrub) unmasked, over the reveal boundary.
///
/// The mask boundary and the visible line come from the same `spec.maskBoundary`
/// points, `LensPlotMap`, and `lensLinePath` interpolation, so they cannot
/// diverge. No image-dependent blend modes, no hardcoded white/black overlays,
/// no parent-view opacity, no opaque card — the composite is deterministic and
/// dark-mode-safe because the base is `Color(.systemBackground)`.
struct LensBackdrop: View {
    let spec: LensPlotSpec
    var photo: UIImage? = nil
    var accent: Color
    var decorativeColors: [Color]
    /// The chart slot rect in this view's own coordinate space (resolved from
    /// the page via an anchor preference). `.zero`/empty until first layout, in
    /// which case the curve modulation and chart marks are skipped and only the
    /// base ramp shows — never a blank frame.
    var plotRect: CGRect = .zero
    var scrubIndex: Int? = nil
    var scrubPoints: [DatedValue] = []
    var scrubCallouts: [String] = []

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            let full = CGRect(origin: .zero, size: size)

            // 1. Semantic base. Everything above is revealed over THIS, so where
            // the mask is 0 the viewer sees pure system background in both light
            // and dark.
            ctx.fill(Path(full), with: .color(Color(.systemBackground)))

            let hasPlot = plotRect.width > 1 && plotRect.height > 1
            let inner = hasPlot ? lensChartInner(plotRect) : .null
            let map = LensPlotMap(x: spec.xDomain, y: spec.yDomain, rect: inner)

            // 2. Decorative layer, drawn into its own layer and clipped by the
            // composite alpha field so the base ctx (and the chart marks below)
            // stay untouched by the mask.
            ctx.drawLayer { deco in
                deco.clipToLayer { mask in
                    // Base vertical ramp over the whole page height.
                    mask.fill(
                        Path(full),
                        with: .linearGradient(
                            Gradient(stops: LensMask.rampStops),
                            startPoint: CGPoint(x: full.midX, y: full.minY),
                            endPoint: CGPoint(x: full.midX, y: full.maxY)
                        )
                    )
                    // Curve modulation: the entire region ABOVE the plotted curve
                    // — up to the very top of the app, hero included — is held at a
                    // stable flat faint value (`aboveCurveCap`), never fading to
                    // nothing. Below the curve the strong reveal ramp is left
                    // intact. Hard edge at the curve.
                    if hasPlot,
                       let boundary = spec.maskBoundary,
                       boundary.count >= 2 {
                        let pts = boundary.map(map.point)
                        var above = lensLinePath(pts, smooth: spec.maskBoundarySmooth)
                        // Extend the "above the line" region to the FULL canvas
                        // width (and up to the very top) so the faint cap covers
                        // the endpoint inset on the right and any inset on the
                        // left — otherwise the strong base ramp shows through as
                        // a bright vertical strip past the chart's data edge.
                        above.addLine(to: CGPoint(x: full.maxX, y: pts.last!.y))
                        above.addLine(to: CGPoint(x: full.maxX, y: full.minY))
                        above.addLine(to: CGPoint(x: full.minX, y: full.minY))
                        above.addLine(to: CGPoint(x: full.minX, y: pts.first!.y))
                        above.closeSubpath()
                        mask.blendMode = .copy
                        mask.fill(above, with: .color(.white.opacity(LensMask.aboveCurveCap)))
                        mask.blendMode = .normal
                    }
                }

                // Decorative content, revealed by the mask alpha.
                if let photo {
                    let image = deco.resolve(Image(uiImage: photo))
                    deco.draw(image, in: aspectFillRect(image.size, in: full))
                    // Deterministic source-over accent tint — fixed opacity,
                    // independent of the photo's luminance (no blend mode).
                    deco.fill(Path(full), with: .color(accent.opacity(photoAccentTint)))
                } else {
                    deco.fill(
                        Path(full),
                        with: .linearGradient(
                            Gradient(colors: decorativeColors),
                            startPoint: CGPoint(x: full.midX, y: full.minY),
                            endPoint: CGPoint(x: full.midX, y: full.maxY)
                        )
                    )
                }
            }

            // 3. Chart marks, unmasked, over the reveal boundary.
            guard hasPlot else { return }
            drawBands(ctx, map: map)
            drawBars(ctx, map: map, plot: inner)
            drawReferences(ctx, map: map, plot: inner)
            drawWhiskers(ctx, map: map)
            drawMarkers(ctx, map: map)
            drawSeries(ctx, map: map)
            drawEndpoint(ctx, map: map)
            drawPointLabels(ctx, map: map, plot: inner)
            drawDateLabels(ctx, map: map, plot: inner)
            drawScrub(ctx, map: map, plot: inner)
        }
        .accessibilityHidden(true)
    }

    /// The lens accent's fixed photo tint opacity — a deterministic source-over
    /// wash applied at a constant strength regardless of the photo's luminance.
    private var photoAccentTint: Double { 0.60 }

    /// Aspect-fill `imageSize` into `rect`, centered — the Canvas equivalent of
    /// `scaledToFill`. Any overflow is clipped by the mask/frame.
    private func aspectFillRect(_ imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    // MARK: Draw passes

    private func drawBands(_ ctx: GraphicsContext, map: LensPlotMap) {
        for band in spec.bands {
            let upper = band.upper.map(map.point)
            let lower = band.lower.map(map.point)
            guard upper.count >= 2, lower.count >= 2 else { continue }
            var path = lensLinePath(upper, smooth: band.smooth)
            let reverseLower = Array(lower.reversed())
            path.addLine(to: reverseLower.first!)
            lensAppendSegments(to: &path, points: reverseLower, smooth: band.smooth)
            path.closeSubpath()
            ctx.fill(path, with: .color(band.color.opacity(band.opacity)))
        }
    }

    private func drawReferences(_ ctx: GraphicsContext, map: LensPlotMap, plot: CGRect) {
        for ref in spec.references {
            var path = Path()
            var labelPoint = CGPoint.zero
            switch ref.kind {
            case .horizontal(let v):
                let y = map.py(v)
                guard y >= plot.minY - 0.5, y <= plot.maxY + 0.5 else { continue }
                path.move(to: CGPoint(x: plot.minX, y: y))
                path.addLine(to: CGPoint(x: plot.maxX, y: y))
                labelPoint = CGPoint(x: plot.maxX, y: y - 8)
            case .vertical(let d):
                let x = map.px(d)
                guard x >= plot.minX - 0.5, x <= plot.maxX + 0.5 else { continue }
                path.move(to: CGPoint(x: x, y: plot.minY))
                path.addLine(to: CGPoint(x: x, y: plot.maxY))
                labelPoint = CGPoint(x: x, y: plot.minY - 2)
            }
            ctx.stroke(
                path,
                with: .color(ref.color),
                style: StrokeStyle(lineWidth: ref.lineWidth, dash: ref.dash ?? [])
            )
            if let label = ref.label {
                let text = ctx.resolve(
                    Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(ref.labelColor)
                )
                let anchor: UnitPoint
                switch ref.kind {
                case .horizontal: anchor = .trailing
                case .vertical: anchor = .bottom
                }
                ctx.draw(text, at: labelPoint, anchor: anchor)
            }
        }
    }

    /// Columns from the baseline to each point's value, with a vertical gradient
    /// anchored to the bar itself.
    private func drawBars(_ ctx: GraphicsContext, map: LensPlotMap, plot: CGRect) {
        for set in spec.bars {
            let baseY = map.py(set.baseline)
            for p in set.points {
                let x = map.px(p.date)
                let valueY = map.py(p.value)
                let top = min(baseY, valueY)
                let height = max(1, abs(valueY - baseY))
                let rect = CGRect(x: x - set.width / 2, y: top, width: set.width, height: height)
                let clipped = rect.intersection(plot.insetBy(dx: -set.width / 2, dy: 0))
                guard !clipped.isNull else { continue }
                let path = Path(roundedRect: clipped, cornerRadius: min(set.cornerRadius, set.width / 2))
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [
                        set.color.opacity(set.opacity),
                        set.color.opacity(set.opacity * 0.45),
                    ]),
                    startPoint: CGPoint(x: clipped.midX, y: clipped.minY),
                    endPoint: CGPoint(x: clipped.midX, y: clipped.maxY)
                )
                ctx.fill(path, with: shading)
            }
        }
    }

    private func drawWhiskers(_ ctx: GraphicsContext, map: LensPlotMap) {
        for w in spec.whiskers {
            let x = map.px(w.date)
            let yLow = map.py(min(w.low, w.high))
            let yHigh = map.py(max(w.low, w.high))
            var path = Path()
            path.move(to: CGPoint(x: x, y: yLow))
            path.addLine(to: CGPoint(x: x, y: yHigh))
            let half = w.capWidth / 2
            for y in [yLow, yHigh] {
                path.move(to: CGPoint(x: x - half, y: y))
                path.addLine(to: CGPoint(x: x + half, y: y))
            }
            ctx.stroke(
                path,
                with: .color(w.color),
                style: StrokeStyle(lineWidth: w.lineWidth, lineCap: .round)
            )
        }
    }

    private func drawMarkers(_ ctx: GraphicsContext, map: LensPlotMap) {
        for set in spec.markerSets {
            for p in set.points {
                let c = map.point(p)
                let r = set.radius
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                if set.hollow {
                    ctx.stroke(Path(ellipseIn: rect), with: .color(set.color), lineWidth: 1.2)
                } else {
                    ctx.fill(Path(ellipseIn: rect), with: .color(set.color))
                }
            }
        }
    }

    private func drawSeries(_ ctx: GraphicsContext, map: LensPlotMap) {
        for s in spec.series {
            let pts = s.points.map(map.point)
            guard pts.count >= 1 else { continue }
            let path = lensLinePath(pts, smooth: s.smooth)
            if let halo = s.haloColor {
                ctx.stroke(
                    path,
                    with: .color(halo.opacity(0.38 * s.opacity)),
                    style: StrokeStyle(
                        lineWidth: s.lineWidth + 3,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: s.dash ?? []
                    )
                )
            }
            ctx.stroke(
                path,
                with: .color(s.color.opacity(s.opacity)),
                style: StrokeStyle(
                    lineWidth: s.lineWidth,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: s.dash ?? []
                )
            )
        }
    }

    private func drawEndpoint(_ ctx: GraphicsContext, map: LensPlotMap) {
        guard let e = spec.endpoint else { return }
        let c = map.point(e.point)
        let r = e.radius
        if e.haloColor != .clear {
            let hr = r + 6
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2)),
                with: .color(e.haloColor.opacity(0.24))
            )
        }
        let ring = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.stroke(Path(ellipseIn: ring), with: .color(e.color), lineWidth: 1.6)
        let ir = r * 0.52
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - ir, y: c.y - ir, width: ir * 2, height: ir * 2)),
            with: .color(e.color)
        )
    }

    /// Selected-point indicator: a thin light vertical rule, an enlarged clean
    /// marker on the line, and a small legible callout.
    private func drawScrub(_ ctx: GraphicsContext, map: LensPlotMap, plot: CGRect) {
        guard let i = scrubIndex, scrubPoints.indices.contains(i) else { return }
        let dv = scrubPoints[i]
        let c = map.point(dv)

        var rule = Path()
        rule.move(to: CGPoint(x: c.x, y: plot.minY))
        rule.addLine(to: CGPoint(x: c.x, y: plot.maxY))
        ctx.stroke(rule, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1))

        let halo: CGFloat = 13
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2)),
            with: .color(.white.opacity(0.16))
        )
        let r: CGFloat = 6
        let dot = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.stroke(Path(ellipseIn: dot.insetBy(dx: -1.6, dy: -1.6)), with: .color(.black.opacity(0.30)), lineWidth: 1.4)
        ctx.fill(Path(ellipseIn: dot), with: .color(.white))

        guard scrubCallouts.indices.contains(i) else { return }
        let resolved = ctx.resolve(
            Text(scrubCallouts[i])
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        )
        let textSize = resolved.measure(in: CGSize(width: plot.width, height: plot.height))
        let above = c.y - r - 8 - textSize.height / 2
        let y = above - textSize.height / 2 < plot.minY ? c.y + r + 8 + textSize.height / 2 : above
        let halfW = textSize.width / 2
        let x = min(max(c.x, plot.minX + halfW + 2), plot.maxX - halfW - 2)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1))
            layer.draw(resolved, at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    private func drawDateLabels(_ ctx: GraphicsContext, map: LensPlotMap, plot: CGRect) {
        for label in spec.dateLabels {
            let x = map.px(label.date)
            let text = ctx.resolve(
                Text(label.text).font(.system(size: 9, weight: .medium)).foregroundStyle(label.color)
            )
            let anchor: UnitPoint
            let drawX: CGFloat
            if x <= plot.minX + 2 {
                anchor = .leading; drawX = plot.minX + 3
            } else if x >= plot.maxX - 2 {
                anchor = .trailing; drawX = plot.maxX - 1
            } else {
                anchor = .center; drawX = x
            }
            ctx.draw(text, at: CGPoint(x: drawX, y: plot.maxY + 12), anchor: anchor)
        }
    }

    private func drawPointLabels(_ ctx: GraphicsContext, map: LensPlotMap, plot: CGRect) {
        for label in spec.pointLabels {
            let point = map.point(label.point)
            let text = ctx.resolve(
                Text(label.text)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(label.color)
            )
            let size = text.measure(in: CGSize(width: plot.width, height: 30))
            let x = min(plot.maxX - size.width - 2, point.x + label.xOffset)
            let y = min(max(point.y, plot.minY + size.height / 2), plot.maxY - size.height / 2)
            ctx.draw(text, at: CGPoint(x: x, y: y), anchor: .leading)
        }
    }
}
