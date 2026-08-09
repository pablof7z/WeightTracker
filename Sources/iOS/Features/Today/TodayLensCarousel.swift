import SwiftUI
import UIKit

// MARK: - Categorical lens accents

extension TodayLens {
    /// Categorical, aesthetic accent — it identifies the lens, it does not grade
    /// the user. No color implies success or failure.
    var accent: Color {
        switch self {
        case .progress: return Color(red: 0.20, green: 0.48, blue: 0.86)
        case .currentWeight: return Color(red: 0.18, green: 0.56, blue: 0.76)
        case .totalLost: return Color(red: 0.26, green: 0.53, blue: 0.39)
        case .thisWeek: return Color(red: 0.90, green: 0.56, blue: 0.16)
        case .weeklyAverage: return Color(red: 0.42, green: 0.47, blue: 0.45)
        case .recentTrend: return Color(red: 0.46, green: 0.37, blue: 0.82)
        case .pace: return Color(red: 0.55, green: 0.32, blue: 0.72)
        case .forecast: return Color(red: 0.38, green: 0.41, blue: 0.83)
        case .fullCut: return Color(red: 0.16, green: 0.50, blue: 0.55)
        case .weeklyRange: return Color(red: 0.53, green: 0.35, blue: 0.55)
        case .weeklyLoss: return Color(red: 0.72, green: 0.40, blue: 0.30)
        }
    }
}

// MARK: - Rendered lens

struct LensStat: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

/// What the hero shows for one hovered point while the user scrubs. Built by
/// the builder in the display unit so the view never converts or formats.
struct LensScrubInfo {
    let heroValue: String
    let heroUnit: String
    /// The hovered date, e.g. "Jul 12" — replaces the live clarifier.
    let heroContext: String
    /// A genuinely useful per-lens comparison, e.g. "vs today +2.1 lb".
    let secondary: String?
}

/// The primary inspectable series for a lens plus the per-point readout. The
/// points are already in the plot's display unit and domain, so the renderer
/// can place the marker with the same mapping it draws the line with.
/// `points`, `info`, and `callouts` are parallel.
struct LensScrubModel {
    let points: [DatedValue]
    let info: [LensScrubInfo]
    let callouts: [String]

    func info(at index: Int) -> LensScrubInfo? {
        info.indices.contains(index) ? info[index] : nil
    }
}

/// Everything the shared composition needs to draw one lens. Produced once from
/// the canonical pipeline; the view never recomputes semantics.
struct RenderedLens {
    let lens: TodayLens
    let heroValue: String
    let heroUnit: String
    let heroContext: String?
    let stats: [LensStat]
    let plot: LensPlotSpec
    let accessibilitySummary: String
    /// Read-only point inspection for this lens. Never mutates data or the
    /// globally selected date.
    var scrub: LensScrubModel? = nil
}

// MARK: - Carousel

struct TodayLensCarousel: View {
    let active: ActiveCut
    let analytics: TodayAnalyticsModel
    let weekly: WeeklyCutChartModel
    let unit: WeightUnit
    let hasEntryToday: Bool
    let dayNumber: Int?
    /// The enabled lenses in the user's saved Settings order. Never empty — the
    /// all-hidden case is resolved to Progress upstream by
    /// `TodayLensOrder.enabled`.
    let lenses: [TodayLens]
    var onToggleUnit: () -> Void
    var onLog: () -> Void
    var onOpenDetail: () -> Void

    @Binding var selection: TodayLens
    /// The hovered scrub index, lifted to `TodayView` so the page's scrub gesture
    /// and the single top-level `LensBackdrop` (which draws the curve + scrub
    /// marks for the selected lens) share one source of truth.
    @Binding var scrubIndex: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            TodayLensPage(
                rendered: builder.render(selection),
                hasEntryToday: hasEntryToday,
                pageIndicator: AnyView(pageIndicator),
                scrubIndex: $scrubIndex,
                heroHorizontalPadding: 58,
                onToggleUnit: onToggleUnit,
                onLog: onLog,
                onOpenDetail: onOpenDetail
            )

            HStack {
                navigationButton(direction: .previous, target: previousLens)
                Spacer()
                navigationButton(direction: .next, target: nextLens)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .frame(height: 104)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var selectionIndex: Int {
        lenses.firstIndex(of: selection) ?? 0
    }

    private var previousLens: TodayLens? {
        let index = selectionIndex - 1
        return lenses.indices.contains(index) ? lenses[index] : nil
    }

    private var nextLens: TodayLens? {
        let index = selectionIndex + 1
        return lenses.indices.contains(index) ? lenses[index] : nil
    }

    private enum NavigationDirection {
        case previous
        case next

        var symbol: String { self == .previous ? "chevron.left" : "chevron.right" }
        var label: String { self == .previous ? "Previous screen" : "Next screen" }
    }

    private func navigationButton(direction: NavigationDirection, target: TodayLens?) -> some View {
        Button {
            guard let target else { return }
            scrubIndex = nil
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                selection = target
            }
        } label: {
            Image(systemName: direction.symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary.opacity(target == nil ? 0.12 : 0.34))
        .disabled(target == nil)
        .accessibilityLabel(direction.label)
        .accessibilityValue(target?.accessibilityName ?? "Unavailable")
    }

    private var builder: TodayLensBuilder {
        TodayLensBuilder(
            active: active,
            analytics: analytics,
            weekly: weekly,
            unit: unit,
            dayNumber: dayNumber
        )
    }

    // Small conventional dots — the active lens is a filled accent dot, the rest
    // are quiet. Never a long capsule.
    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(lenses) { lens in
                Circle()
                    .fill(lens == selection ? selection.accent : Color.secondary.opacity(0.30))
                    .frame(width: 6, height: 6)
                    .scaleEffect(lens == selection ? 1.15 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
        .accessibilityHidden(true)
    }

}

// MARK: - Shared lens composition (hero + full-bleed chart + supporting shelf)

private struct TodayLensPage: View {
    let rendered: RenderedLens
    let hasEntryToday: Bool
    let pageIndicator: AnyView
    /// Hovered point index during a scrub, shared with the top-level backdrop so
    /// the curve's scrub marker and this page's hero readout stay in lockstep.
    /// Read-only: it never changes the globally selected date or any stored data.
    var scrubIndex: Binding<Int?> = .constant(nil)
    /// Whether this page contributes its chart-slot rect to the shared
    /// `PlotRectKey` preference (only the centered page does).
    var publishesRect: Bool = true
    /// Leaves room for the screen-switching arrows in the live carousel while
    /// keeping standalone previews and snapshots at their original width.
    var heroHorizontalPadding: CGFloat = 22
    /// `ImageRenderer` cannot render a UIKit gesture recognizer host and draws
    /// a warning placeholder in its place. Snapshot/previews disable only that
    /// transparent interaction layer; the chart geometry remains identical.
    var allowsChartInteraction: Bool = true
    var onToggleUnit: () -> Void
    var onLog: () -> Void
    var onOpenDetail: () -> Void

    /// The readout for the currently hovered point, or nil when not scrubbing.
    private var scrubInfo: LensScrubInfo? {
        guard let index = scrubIndex.wrappedValue, let model = rendered.scrub else { return nil }
        return model.info(at: index)
    }

    var body: some View {
        // The lens page is the foreground composite only: the hero, page dots, a
        // transparent chart slot (which owns the gestures and publishes its rect),
        // and the de-carded metrics, laid out in a VStack. The ONE decorative
        // masked canvas + chart is drawn by the top-level `LensBackdrop` in
        // `TodayView`, so it can bleed behind the status bar and the custom top
        // bar — a per-page background is clipped below the top bar and cannot.
        VStack(spacing: 0) {
            hero
                .padding(.horizontal, heroHorizontalPadding)
                .padding(.top, 6)

            pageIndicator
                .padding(.top, 12)
                .padding(.bottom, 2)

            chartSlot

            metricsRow
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rendered.accessibilitySummary)
        .accessibilityHint("Use the arrows beside the headline for another perspective. Double tap the chart to open the detailed view.")
    }

    /// The transparent chart region. It reserves the flexible middle space, owns
    /// the tap-to-open-detail and hold-to-scrub gestures, and reports its bounds
    /// (via the anchor preference) so `LensBackdrop` draws the chart there.
    private var chartSlot: some View {
        GeometryReader { g in
            // Scrub is driven by a UIKit UILongPressGestureRecognizer so a brief
            // hold can become a continuous horizontal point inspection without
            // competing with any screen-level swipe navigation. Once begun it
            // keeps reporting the finger location, which we map to the nearest
            // point. A short tap still opens the detail chart.
            Group {
                if allowsChartInteraction {
                    ScrubGestureView(
                        onTap: { onOpenDetail() },
                        onBegan: { p in
                            updateScrub(toX: p.x, size: g.size)
                        },
                        onChanged: { p in updateScrub(toX: p.x, size: g.size) },
                        onEnded: {
                            scrubIndex.wrappedValue = nil
                        }
                    )
                } else {
                    Color.clear
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .anchorPreference(key: PlotRectKey.self, value: .bounds) { publishesRect ? $0 : nil }
        // Light selection tick on each point change only — never continuous.
        .sensoryFeedback(.selection, trigger: scrubIndex.wrappedValue)
    }

    // MARK: Hit testing

    /// Nearest primary-series point to the finger's x, using the same inner-rect
    /// mapping `LensBackdrop` draws with (the slot's local origin matches the
    /// canvas's x origin, so only x is needed).
    private func nearestScrubIndex(toX x: CGFloat, size: CGSize) -> Int? {
        let points = rendered.scrub?.points ?? []
        guard !points.isEmpty else { return nil }
        let inner = lensChartInner(CGRect(origin: .zero, size: size))
        let map = LensPlotMap(x: rendered.plot.xDomain, y: rendered.plot.yDomain, rect: inner)
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, p) in points.enumerated() {
            let d = abs(map.px(p.date) - x)
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }

    /// Maps the finger's x to the nearest point and updates the scrub index.
    private func updateScrub(toX x: CGFloat, size: CGSize) {
        let index = nearestScrubIndex(toX: x, size: size)
        if index != scrubIndex.wrappedValue { scrubIndex.wrappedValue = index }
    }

    // Hero: one large centered number + unit, then a single clarifier line. No
    // uppercase heading — the value is self-explanatory. Tap toggles the unit;
    // long-press opens weight entry.
    private var hero: some View {
        // While scrubbing, the hovered point owns the headline on every lens —
        // value, date clarifier, and a contextual comparison. Release restores
        // the canonical aggregate headline.
        let scrub = scrubInfo
        let valueText = scrub?.heroValue ?? rendered.heroValue
        let unitText = scrub?.heroUnit ?? rendered.heroUnit
        let context = scrub?.heroContext ?? rendered.heroContext

        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(valueText)
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(unitText)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleUnit() }
            .onLongPressGesture(minimumDuration: 0.35) { onLog() }

            if let context {
                Text(context)
                    .font(.system(size: 16, weight: scrub != nil ? .semibold : .regular))
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }

            // The per-lens contextual comparison for the hovered point. It takes
            // the slot the "Log today" affordance normally occupies, so the hero
            // never grows or reflows mid-scrub.
            if let secondary = scrub?.secondary {
                Text(secondary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
                    .padding(.top, 2)
            }

            if scrub == nil, !hasEntryToday {
                Button(action: onLog) {
                    Label("Log today", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(rendered.lens.accent)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // De-carded supporting figures: three values rendered directly over the
    // darkened lower canvas — light labels, large monospaced values, thin
    // low-opacity separators. No rounded rect, no shadow, no background.
    private var metricsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(rendered.stats.enumerated()), id: \.element.id) { index, stat in
                VStack(spacing: 3) {
                    Text(stat.label.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(stat.value)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .frame(maxWidth: .infinity)

                if index < rendered.stats.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 1, height: 30)
                }
            }
        }
    }
}

// MARK: - Scrub gesture (UIKit)

/// A transparent overlay whose scrub is driven by a `UILongPressGestureRecognizer`.
/// It begins after a brief near-stationary hold, then keeps reporting `location`
/// as the finger moves, which is exactly what point inspection needs. A separate
/// tap recognizer opens the detail chart.
struct ScrubGestureView: UIViewRepresentable {
    var onTap: () -> Void
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePress(_:))
        )
        press.minimumPressDuration = 0.28
        press.allowableMovement = 12
        press.delegate = context.coordinator
        view.addGestureRecognizer(press)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ScrubGestureView
        init(_ parent: ScrubGestureView) { self.parent = parent }

        @objc func handlePress(_ g: UILongPressGestureRecognizer) {
            let location = g.location(in: g.view)
            switch g.state {
            case .began: parent.onBegan(location)
            case .changed: parent.onChanged(location)
            case .ended, .cancelled, .failed: parent.onEnded()
            default: break
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            if g.state == .ended { parent.onTap() }
        }

        // Keep the tap and press recognizers cooperative with ancestor gestures.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

// MARK: - Chart-slot geometry

/// Carries the chart slot's bounds up to the page background so `LensBackdrop`
/// can draw its marks — and the decorative curve modulation — in exactly the
/// rect the layout gave the chart. An anchor resolves synchronously during
/// layout, so it works under `ImageRenderer` (snapshots) without a state
/// round-trip.
struct PlotRectKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Top-level decorative backdrop host

extension View {
    /// Hosts the single decorative backdrop + chart for one rendered lens as a
    /// full-screen background that bleeds behind EVERY safe area — the status
    /// bar, the custom top control row, and the home indicator. It resolves the
    /// chart-slot rect published by the centered page via `PlotRectKey` inside a
    /// full-screen proxy, so the plotted curve lands in the on-screen slot even
    /// though the backdrop itself is hosted above the top bar (where a per-page
    /// `.background` would be clipped). Pass `rendered == nil` for the no-lens
    /// fallback (plain system background).
    @ViewBuilder
    func lensBackdrop(rendered: RenderedLens?, photo: UIImage?, scrubIndex: Int?) -> some View {
        backgroundPreferenceValue(PlotRectKey.self) { anchor in
            GeometryReader { proxy in
                if let rendered {
                    LensBackdrop(
                        spec: rendered.plot,
                        photo: photo,
                        accent: rendered.lens.accent,
                        decorativeColors: rendered.lens.decorativeColors,
                        plotRect: anchor.map { proxy[$0] } ?? .zero,
                        scrubIndex: scrubIndex,
                        scrubPoints: rendered.scrub?.points ?? [],
                        scrubCallouts: rendered.scrub?.callouts ?? []
                    )
                } else {
                    Color(.systemBackground)
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
enum LensPreviewFixture {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    static func date(_ s: String) -> Date {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"; return f.date(from: s)!
    }
    static let asOf = date("2026-07-17")

    static var active: ActiveCut {
        ActiveCut(
            startDate: date("2026-04-28"),
            startWeightKg: UnitConvert.lbToKg(174.5),
            targetWeightKg: UnitConvert.lbToKg(150),
            targetEndDate: date("2026-08-21")
        )
    }

    static var readings: [Reading] {
        let csv = """
        2026-04-28,174.5 2026-05-02,174.2 2026-05-06,174.0 2026-05-10,173.6
        2026-05-13,171.8 2026-05-16,170.0 2026-05-19,169.2 2026-05-22,168.4
        2026-05-25,168.6 2026-05-28,166.6 2026-05-31,164.7 2026-06-03,163.9
        2026-06-06,165.3 2026-06-09,165.4 2026-06-12,162.6 2026-06-15,165.0
        2026-06-18,161.5 2026-06-21,162.4 2026-06-24,160.9 2026-06-27,161.0
        2026-06-30,159.8 2026-07-03,159.0 2026-07-05,159.8 2026-07-06,159.3
        2026-07-07,159.4 2026-07-08,157.4 2026-07-09,158.0 2026-07-10,157.8
        2026-07-11,157.3 2026-07-12,157.0 2026-07-13,157.4 2026-07-14,155.8
        2026-07-15,155.0 2026-07-16,156.9 2026-07-17,156.2
        """
        return csv.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { token in
            let cols = token.split(separator: ",")
            let d = date(String(cols[0]))
            let r = Reading(date: d, weightKg: UnitConvert.lbToKg(Double(cols[1])!), source: .importCSV)
            r.date = d
            return r
        }
    }

    static var projection: CutProjectionResult {
        let anchor = date("2026-07-17")
        return CutProjectionResult(
            anchorDate: anchor,
            anchorKg: UnitConvert.lbToKg(156.6),
            isTargetReached: false,
            qualifyingHistoricalCount: 2,
            bestEndKg: UnitConvert.lbToKg(148.3),
            avgPath: [(anchor, UnitConvert.lbToKg(156.6)), (date("2026-08-21"), UnitConvert.lbToKg(150.3))],
            worstEndKg: UnitConvert.lbToKg(153.4),
            targetWeightKg: UnitConvert.lbToKg(150),
            targetEndDate: date("2026-08-21")
        )
    }

    static var chart: CutChartModel {
        CutChartModel.prepare(active: active, readings: readings, projection: projection, calendar: calendar)
    }
    static var domains: CutChartDomainState { .resolved(for: chart, calendar: calendar) }
    static var weekly: WeeklyCutChartModel { .prepare(active: active, readings: readings, asOf: asOf, calendar: calendar) }
    static var analytics: TodayAnalyticsModel { .prepare(active: active, readings: readings, asOf: asOf, calendar: calendar) }

    static func builder(_ unit: WeightUnit) -> TodayLensBuilder {
        TodayLensBuilder(active: active, analytics: analytics, weekly: weekly,
                         unit: unit, dayNumber: 81, calendar: calendar)
    }
}

/// Fixed-size lens page used by previews and the snapshot test so the exported
/// artifacts match what previews show.
@MainActor
func makeLensSnapshotView(_ lens: TodayLens, unit: WeightUnit) -> some View {
    // The decorative-masked backdrop now lives in a top-level `.lensBackdrop`
    // modifier so it can bleed behind the bars in the app; the snapshot composes
    // the same modifier over the page. Photo mode is off here so snapshots
    // exercise the deterministic accent-gradient path.
    let rendered = LensPreviewFixture.builder(unit).render(lens)
    return TodayLensPage(
        rendered: rendered,
        hasEntryToday: true,
        pageIndicator: AnyView(EmptyView()),
        allowsChartInteraction: false,
        onToggleUnit: {}, onLog: {}, onOpenDetail: {}
    )
    .frame(width: 393, height: 640)
    .lensBackdrop(rendered: rendered, photo: nil, scrubIndex: nil)
    .background(Color(.systemBackground))
}

@MainActor
private func lensPreview(_ lens: TodayLens, _ unit: WeightUnit) -> some View {
    let rendered = LensPreviewFixture.builder(unit).render(lens)
    return TodayLensPage(
        rendered: rendered,
        hasEntryToday: true,
        pageIndicator: AnyView(EmptyView()),
        allowsChartInteraction: false,
        onToggleUnit: {}, onLog: {}, onOpenDetail: {}
    )
    .frame(height: 560)
    .lensBackdrop(rendered: rendered, photo: nil, scrubIndex: nil)
    .background(Color(.systemBackground))
}

#Preview("1 · Progress vs Plan · lb") { lensPreview(.progress, .lbs) }
#Preview("2 · Recent Trend · lb") { lensPreview(.recentTrend, .lbs) }
#Preview("3 · Week-to-Date Average · lb") { lensPreview(.weeklyAverage, .lbs) }
#Preview("4 · Week-over-Week Change · lb") { lensPreview(.weeklyLoss, .lbs) }

#Preview("Progress · dark · kg") { lensPreview(.progress, .kg).preferredColorScheme(.dark) }
#Preview("Recent Trend · dark · kg") { lensPreview(.recentTrend, .kg).preferredColorScheme(.dark) }

#Preview("Carousel") {
    @Previewable @State var selection: TodayLens = .progress
    @Previewable @State var scrubIndex: Int? = nil
    return TodayLensCarousel(
        active: LensPreviewFixture.active,
        analytics: LensPreviewFixture.analytics,
        weekly: LensPreviewFixture.weekly,
        unit: .lbs,
        hasEntryToday: true,
        dayNumber: 81,
        lenses: TodayLens.allCases,
        onToggleUnit: {}, onLog: {}, onOpenDetail: {},
        selection: $selection,
        scrubIndex: $scrubIndex
    )
}
#endif
