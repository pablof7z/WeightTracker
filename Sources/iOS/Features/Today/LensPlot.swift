import SwiftUI

// MARK: - Plot spec

/// A declarative description of one full-bleed Today lens chart. Every visible
/// line and its area fill are generated from the *same* points with the *same*
/// interpolation, so the fill boundary can never diverge from the line. Fills
/// are gradients anchored to the whole plot rectangle — not to a mark's local
/// data bounds — which is what keeps them atmospheric instead of a compressed
/// slab of color.
struct LensPlotSpec {
    var xDomain: ClosedRange<Date>
    var yDomain: ClosedRange<Double>
    var fills: [Fill] = []
    var bands: [Band] = []
    var references: [Reference] = []
    var bars: [BarSet] = []
    var whiskers: [Whisker] = []
    var markerSets: [MarkerSet] = []
    var series: [Series] = []
    var endpoint: Endpoint?
    var dateLabels: [DateLabel] = []

    struct Series: Identifiable {
        let id = UUID()
        var points: [DatedValue]
        var color: Color
        var lineWidth: CGFloat = 2.6
        var dash: [CGFloat]?
        var smooth: Bool = true
        var opacity: Double = 1
        /// Optional dark halo stroked underneath the line so a white primary
        /// series stays legible over both the pale top and the navy floor of
        /// the atmospheric background.
        var haloColor: Color? = nil
    }

    /// Area between a line and a baseline, filled with a plot-rect gradient.
    struct Fill {
        var points: [DatedValue]
        var baseline: Baseline
        var color: Color
        var topOpacity: Double = 0.26
        var smooth: Bool = true
    }

    enum Baseline: Equatable {
        case value(Double)
        case plotBottom
    }

    /// Area between two lines (forecast lower/upper). Zero-width at the anchor,
    /// widening into the future by construction.
    struct Band {
        var lower: [DatedValue]
        var upper: [DatedValue]
        var color: Color
        var opacity: Double = 0.13
        var smooth: Bool = true
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
}

// MARK: - The renderer

/// Full-bleed, edge-to-edge lens chart. No card, no rounded container, no
/// left y-axis gutter. A small internal inset keeps line caps and markers from
/// clipping while the canvas itself still reads to the screen edges.
struct LensPlot: View {
    let spec: LensPlotSpec
    /// Reduce Motion swaps the draw-on animation for a plain crossfade. The
    /// value flows in from the environment at the call site.
    var animateProgress: Double = 1

    // MARK: Scrubbing (point inspection)
    //
    // The primary inspectable series for this lens, already in the plot's
    // display unit and domain, plus a parallel callout string per point. The
    // plot owns hit-testing because it owns the data↔plot coordinate mapping;
    // the hovered index is published upward so the hero can morph.
    var scrubPoints: [DatedValue] = []
    var scrubCallouts: [String] = []
    @Binding var scrubIndex: Int?
    /// Fires when a hold-then-drag begins/ends so the carousel can suppress
    /// paging for the duration of the scrub.
    var onScrubbingChanged: (Bool) -> Void = { _ in }

    // Internal data insets (points). Leading is 0 so the line/fill reach the
    // very left edge (the round cap's clipped half is imperceptible); the right
    // keeps a hair of room for the endpoint ring, and top/bottom are tight so
    // the curve fills the canvas rather than floating in dead space.
    private let insetLeading: CGFloat = 0
    private let insetTrailing: CGFloat = 7
    private let insetTop: CGFloat = 8
    private let insetBottom: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
                let plot = plotRect(for: size)
                let map = PlotMap(x: spec.xDomain, y: spec.yDomain, rect: plot)

                drawFills(ctx, map: map, plot: plot)
                drawBands(ctx, map: map)
                drawBars(ctx, map: map, plot: plot)
                drawReferences(ctx, map: map, plot: plot)
                drawWhiskers(ctx, map: map)
                drawMarkers(ctx, map: map)
                drawSeries(ctx, map: map)
                drawEndpoint(ctx, map: map)
                drawDateLabels(ctx, map: map, plot: plot)
                drawScrub(ctx, map: map, plot: plot)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // The scrub must win the touch over the carousel's paging swipe.
            // Sequencing a long press *before* a zero-distance drag means the
            // finger is stationary during recognition (so the pager never
            // starts), and once the press succeeds this high-priority gesture
            // owns every subsequent horizontal movement.
            .highPriorityGesture(scrubGesture(size: geo.size))
        }
        .accessibilityHidden(true) // The hero + supporting figures carry the data.
    }

    private func plotRect(for size: CGSize) -> CGRect {
        CGRect(
            x: insetLeading,
            y: insetTop,
            width: max(1, size.width - insetLeading - insetTrailing),
            height: max(1, size.height - insetTop - insetBottom)
        )
    }

    // MARK: Scrub gesture + hit testing

    private func scrubGesture(size: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.28, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                onScrubbingChanged(true)
                // `minimumDistance: 0` delivers the touch location immediately
                // after the press succeeds, so the marker lands under the finger
                // without waiting for movement.
                guard let drag else { return }
                let index = nearestIndex(toX: drag.location.x, size: size)
                if index != scrubIndex { scrubIndex = index }
            }
            .onEnded { _ in
                scrubIndex = nil
                onScrubbingChanged(false)
            }
    }

    /// Nearest point in the primary inspectable series to the finger's x, using
    /// the same mapping the renderer draws with.
    private func nearestIndex(toX x: CGFloat, size: CGSize) -> Int? {
        guard !scrubPoints.isEmpty else { return nil }
        let map = PlotMap(x: spec.xDomain, y: spec.yDomain, rect: plotRect(for: size))
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, p) in scrubPoints.enumerated() {
            let d = abs(map.px(p.date) - x)
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }

    // MARK: Coordinate mapping

    private struct PlotMap {
        let x: ClosedRange<Date>
        let y: ClosedRange<Double>
        let rect: CGRect

        func point(_ dv: DatedValue) -> CGPoint {
            CGPoint(x: px(dv.date), y: py(dv.value))
        }
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

    // MARK: Path generation (shared by line and fill)

    /// One generator for every line and every fill boundary. Catmull-Rom when
    /// smoothing, straight segments otherwise. Because the fill re-invokes this
    /// with the identical points, the boundary geometry is guaranteed to match.
    private func linePath(_ points: [CGPoint], smooth: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        appendSegments(to: &path, points: points, smooth: smooth)
        return path
    }

    /// Appends the segments for `points` to `path`, continuing from its current
    /// point (no `move`). Used to trace a band's return boundary as one
    /// continuous subpath. Catmull-Rom when smoothing, straight otherwise.
    private func appendSegments(to path: inout Path, points: [CGPoint], smooth: Bool) {
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

    // MARK: Draw passes

    private func drawFills(_ ctx: GraphicsContext, map: PlotMap, plot: CGRect) {
        for fill in spec.fills {
            let pts = fill.points.map(map.point)
            guard pts.count >= 2 else { continue }
            let baselineY: CGFloat
            switch fill.baseline {
            case .value(let v): baselineY = map.py(v)
            case .plotBottom: baselineY = plot.maxY
            }
            var area = linePath(pts, smooth: fill.smooth)
            area.addLine(to: CGPoint(x: pts.last!.x, y: baselineY))
            area.addLine(to: CGPoint(x: pts.first!.x, y: baselineY))
            area.closeSubpath()

            // Gradient anchored to the FULL plot rectangle, strongest at the top
            // and fading to transparent deeper in the plot — never compressed to
            // the mark's own bounds.
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [
                    fill.color.opacity(fill.topOpacity),
                    fill.color.opacity(fill.topOpacity * 0.35),
                    fill.color.opacity(0),
                ]),
                startPoint: CGPoint(x: plot.midX, y: plot.minY),
                endPoint: CGPoint(x: plot.midX, y: plot.maxY)
            )
            ctx.fill(area, with: shading)
        }
    }

    private func drawBands(_ ctx: GraphicsContext, map: PlotMap) {
        for band in spec.bands {
            let upper = band.upper.map(map.point)
            let lower = band.lower.map(map.point)
            guard upper.count >= 2, lower.count >= 2 else { continue }
            // One continuous polygon: forward along the upper boundary, down to
            // the lower boundary's end, back along the lower boundary, close.
            var path = linePath(upper, smooth: band.smooth)
            let reverseLower = Array(lower.reversed())
            path.addLine(to: reverseLower.first!)
            appendSegments(to: &path, points: reverseLower, smooth: band.smooth)
            path.closeSubpath()
            ctx.fill(path, with: .color(band.color.opacity(band.opacity)))
        }
    }

    private func drawReferences(_ ctx: GraphicsContext, map: PlotMap, plot: CGRect) {
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

    /// Columns from the baseline to each point's value. A vertical gradient
    /// anchored to the bar itself keeps them atmospheric rather than flat slabs,
    /// matching how the area fills read.
    private func drawBars(_ ctx: GraphicsContext, map: PlotMap, plot: CGRect) {
        for set in spec.bars {
            let baseY = map.py(set.baseline)
            for p in set.points {
                let x = map.px(p.date)
                let valueY = map.py(p.value)
                let top = min(baseY, valueY)
                let height = max(1, abs(valueY - baseY))
                let rect = CGRect(x: x - set.width / 2, y: top, width: set.width, height: height)
                // Keep bars inside the plot so an outlier never bleeds off-canvas.
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

    /// Per-point low→high segments with subtle end caps.
    private func drawWhiskers(_ ctx: GraphicsContext, map: PlotMap) {
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

    private func drawMarkers(_ ctx: GraphicsContext, map: PlotMap) {
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

    private func drawSeries(_ ctx: GraphicsContext, map: PlotMap) {
        for s in spec.series {
            let pts = s.points.map(map.point)
            guard pts.count >= 1 else { continue }
            let path = linePath(pts, smooth: s.smooth)
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

    private func drawEndpoint(_ ctx: GraphicsContext, map: PlotMap) {
        guard let e = spec.endpoint else { return }
        let c = map.point(e.point)
        let r = e.radius
        // Restrained current marker over the dark canvas: a subtle accent halo,
        // a thin ring, and a small solid inner dot — no oversized bubble and no
        // opaque background fill that would punch a hole in the gradient.
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
    /// marker on the line, and a small legible callout over the gradient. No
    /// tooltip chrome — white text with a soft shadow is enough.
    private func drawScrub(_ ctx: GraphicsContext, map: PlotMap, plot: CGRect) {
        guard let i = scrubIndex, scrubPoints.indices.contains(i) else { return }
        let dv = scrubPoints[i]
        let c = map.point(dv)

        var rule = Path()
        rule.move(to: CGPoint(x: c.x, y: plot.minY))
        rule.addLine(to: CGPoint(x: c.x, y: plot.maxY))
        ctx.stroke(rule, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1))

        // Enlarged marker: soft halo, solid core, thin dark outline so it stays
        // readable against both the pale top and the navy floor.
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
        // Sit above the marker, flipping below when it would clip the top, and
        // clamp horizontally so it never runs off either edge.
        let above = c.y - r - 8 - textSize.height / 2
        let y = above - textSize.height / 2 < plot.minY ? c.y + r + 8 + textSize.height / 2 : above
        let halfW = textSize.width / 2
        let x = min(max(c.x, plot.minX + halfW + 2), plot.maxX - halfW - 2)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1))
            layer.draw(resolved, at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    private func drawDateLabels(_ ctx: GraphicsContext, map: PlotMap, plot: CGRect) {
        for label in spec.dateLabels {
            let x = map.px(label.date)
            let text = ctx.resolve(
                Text(label.text).font(.system(size: 9, weight: .medium)).foregroundStyle(label.color)
            )
            // Edge labels anchor to the edges so they never clip now that the
            // plot runs to x = 0; interior labels stay centered on their date.
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
}
