import SwiftUI

// MARK: - Categorical lens accents

extension TodayLens {
    /// Categorical, aesthetic accent — it identifies the lens, it does not grade
    /// the user. No color implies success or failure.
    var accent: Color {
        switch self {
        case .currentWeight: return Color(red: 0.20, green: 0.48, blue: 0.86) // cool blue
        case .totalLost:     return Color(red: 0.26, green: 0.53, blue: 0.39) // forest / sage
        case .thisWeek:      return Color(red: 0.90, green: 0.56, blue: 0.16) // amber
        case .weeklyAverage: return Color(red: 0.42, green: 0.47, blue: 0.45) // sage / charcoal
        case .pace:          return Color(red: 0.46, green: 0.37, blue: 0.82) // violet / indigo
        case .forecast:      return Color(red: 0.38, green: 0.41, blue: 0.83) // blue-violet
        case .fullCut:       return Color(red: 0.16, green: 0.50, blue: 0.55) // deep teal
        case .weeklyRange:   return Color(red: 0.53, green: 0.35, blue: 0.55) // plum
        case .weeklyLoss:    return Color(red: 0.72, green: 0.40, blue: 0.30) // clay / terracotta
        }
    }
}

// MARK: - Rendered lens

struct LensStat: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

/// Date-aware hero override for the Current Weight lens. Shows the *selected
/// day's* logged weight, or a muted placeholder (most-recent reading) with a
/// tap-to-log cue when that day has no entry.
struct CurrentWeightHero: Equatable {
    let valueText: String
    let unit: String
    /// Nil when there's nothing worth stating in words: today's unlogged state
    /// is already carried by the muted value color, so no caption is shown.
    let context: String?
    let logged: Bool
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
    let projection: CutProjectionResult
    let chart: CutChartModel
    let domains: CutChartDomainState
    let weekly: WeeklyCutChartModel
    let pace: PaceLensModel
    let thisWeek: ThisWeekModel
    let unit: WeightUnit
    let hasEntryToday: Bool
    let dayNumber: Int?
    /// The day the user is viewing (defaults to today), its logged value in the
    /// display unit, whether that day has an entry, and its cut-day number —
    /// all drive the date-aware Current Weight hero.
    let selectedDate: Date
    let selectedDayValue: Double
    let selectedDayLogged: Bool
    let selectedDayNumber: Int?
    /// The enabled lenses in the user's saved Settings order. Never empty — the
    /// all-hidden case is resolved to Current Weight upstream by
    /// `TodayLensOrder.enabled`.
    let lenses: [TodayLens]
    var onToggleUnit: () -> Void
    var onLog: () -> Void
    var onOpenDetail: () -> Void

    @Binding var selection: TodayLens

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let heroDate: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d, yyyy"); return f
    }()

    /// True while a hold-then-drag point inspection owns the touch. Paging is
    /// suppressed for the duration so the scrub never flips lenses.
    @State private var isScrubbing = false

    var body: some View {
        TabView(selection: $selection) {
            ForEach(lenses) { lens in
                TodayLensPage(
                    rendered: builder.render(lens),
                    hasEntryToday: hasEntryToday,
                    pageIndicator: AnyView(pageIndicator),
                    currentWeightHero: lens == .currentWeight ? currentWeightHero : nil,
                    isScrubbing: $isScrubbing,
                    onToggleUnit: onToggleUnit,
                    onLog: onLog,
                    onOpenDetail: onOpenDetail
                )
                .tag(lens)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.container, edges: .bottom)
        // Belt-and-braces with the chart's high-priority gesture: the pager is
        // also told to stand down for the duration of a scrub.
        .scrollDisabled(isScrubbing)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var currentWeightHero: CurrentWeightHero {
        let value = String(format: "%.1f", selectedDayValue)
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let dateStr = Self.heroDate.string(from: selectedDate)
        let context: String?
        if selectedDayLogged {
            if let n = selectedDayNumber {
                context = "\(dateStr) · Day \(n)"
            } else {
                context = dateStr
            }
        } else if isToday {
            // The muted value color already says "not logged"; a tap anywhere
            // on the hero logs it, so no caption is needed.
            context = nil
        } else {
            // Still muted-color-implies-unlogged; the date is real information
            // (which day is being browsed), so it stays.
            context = dateStr
        }
        return CurrentWeightHero(valueText: value, unit: unit.symbol, context: context, logged: selectedDayLogged)
    }

    private var builder: TodayLensBuilder {
        TodayLensBuilder(
            active: active,
            projection: projection,
            chart: chart,
            domains: domains,
            weekly: weekly,
            pace: pace,
            thisWeek: thisWeek,
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
    var currentWeightHero: CurrentWeightHero? = nil
    /// Lifted to the carousel so the pager can be gated while scrubbing.
    var isScrubbing: Binding<Bool>? = nil
    var onToggleUnit: () -> Void
    var onLog: () -> Void
    var onOpenDetail: () -> Void

    /// Hovered point index during a scrub. Per-page and read-only: it never
    /// changes the globally selected date or any stored data.
    @State private var scrubIndex: Int? = nil

    /// The readout for the currently hovered point, or nil when not scrubbing.
    private var scrubInfo: LensScrubInfo? {
        guard let index = scrubIndex, let model = rendered.scrub else { return nil }
        return model.info(at: index)
    }

    var body: some View {
        // The page is transparent: the ONE continuous canvas background lives at
        // the screen level (behind the nav bar too) and stays spatially stable
        // while pages slide, so the hero, chart, dots, and de-carded metrics all
        // sit over the same gradient with no seam.
        VStack(spacing: 0) {
            hero
                .padding(.horizontal, 22)
                .padding(.top, 6)

            pageIndicator
                .padding(.top, 12)
                .padding(.bottom, 2)

            LensPlot(
                spec: rendered.plot,
                scrubPoints: rendered.scrub?.points ?? [],
                scrubCallouts: rendered.scrub?.callouts ?? [],
                scrubIndex: $scrubIndex,
                onScrubbingChanged: { active in
                    isScrubbing?.wrappedValue = active
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // A short tap still opens the detail chart; only a deliberate hold
            // starts a scrub.
            .onTapGesture { onOpenDetail() }
            // Light selection tick on each point change only — never continuous.
            .sensoryFeedback(.selection, trigger: scrubIndex)

            metricsRow
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rendered.accessibilitySummary)
        .accessibilityHint("Swipe left or right for another perspective. Double tap the chart to open the detailed view.")
    }

    // Hero: one large centered number + unit, then a single clarifier line. No
    // uppercase heading — the value is self-explanatory. Tap toggles the unit;
    // long-press opens weight entry.
    private var hero: some View {
        // Current Weight reflects the *selected day's* logged weight: full
        // opacity when that day is logged, or a muted placeholder (the most
        // recent reading) with a tap-to-log cue when it is not — so the screen
        // never presents an old reading as if it were today's. Other lenses keep
        // their aggregate headline.
        // While scrubbing, the hovered point owns the headline on every lens —
        // value, date clarifier, and a contextual comparison — and the live
        // placeholder/muting rules are suspended. Release restores all of it.
        let scrub = scrubInfo
        let cw = currentWeightHero
        let valueText = scrub?.heroValue ?? cw?.valueText ?? rendered.heroValue
        let unitText = scrub?.heroUnit ?? cw?.unit ?? rendered.heroUnit
        let context = scrub?.heroContext ?? cw?.context ?? rendered.heroContext
        let muted = scrub == nil ? (cw.map { !$0.logged } ?? false) : false
        let tapLogs = muted

        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(valueText)
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .opacity(muted ? 0.34 : 1)
                Text(unitText)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(muted ? 0.6 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .contentShape(Rectangle())
            .onTapGesture { tapLogs ? onLog() : onToggleUnit() }
            .onLongPressGesture(minimumDuration: 0.35) { onLog() }

            if let context {
                Text(context)
                    .font(.system(size: 16, weight: muted || scrub != nil ? .semibold : .regular))
                    .foregroundStyle(muted ? rendered.lens.accent : Color.secondary)
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

            // Aggregate lenses keep a discrete "Log today" affordance; Current
            // Weight's muted placeholder already carries the tap-to-log cue.
            if scrub == nil, cw == nil, !hasEntryToday {
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
    static var pace: PaceLensModel { .prepare(active: active, readings: readings, projection: projection, asOf: asOf, calendar: calendar) }
    static var thisWeek: ThisWeekModel { .prepare(active: active, readings: readings, asOf: asOf, calendar: calendar) }

    static func builder(_ unit: WeightUnit) -> TodayLensBuilder {
        TodayLensBuilder(active: active, projection: projection, chart: chart, domains: domains,
                         weekly: weekly, pace: pace, thisWeek: thisWeek, unit: unit, dayNumber: 81, calendar: calendar)
    }
}

/// Fixed-size lens page used by previews and the snapshot test so the exported
/// artifacts match what previews show.
@MainActor
func makeLensSnapshotView(_ lens: TodayLens, unit: WeightUnit) -> some View {
    ZStack {
        LensCanvasBackground(lens: lens)
        TodayLensPage(
            rendered: LensPreviewFixture.builder(unit).render(lens),
            hasEntryToday: true,
            pageIndicator: AnyView(EmptyView()),
            onToggleUnit: {}, onLog: {}, onOpenDetail: {}
        )
    }
    .frame(width: 393, height: 640)
}

@MainActor
private func lensPreview(_ lens: TodayLens, _ unit: WeightUnit) -> some View {
    ZStack {
        LensCanvasBackground(lens: lens)
        TodayLensPage(
            rendered: LensPreviewFixture.builder(unit).render(lens),
            hasEntryToday: true,
            pageIndicator: AnyView(EmptyView()),
            onToggleUnit: {}, onLog: {}, onOpenDetail: {}
        )
    }
    .frame(height: 560)
}

#Preview("1 · Current Weight · lb") { lensPreview(.currentWeight, .lbs) }
#Preview("2 · Total Lost · lb") { lensPreview(.totalLost, .lbs) }
#Preview("3 · This Week · lb") { lensPreview(.thisWeek, .lbs) }
#Preview("4 · Weekly Average · lb") { lensPreview(.weeklyAverage, .lbs) }
#Preview("5 · Pace · lb") { lensPreview(.pace, .lbs) }
#Preview("6 · Forecast · lb") { lensPreview(.forecast, .lbs) }
#Preview("7 · Full Cut · lb") { lensPreview(.fullCut, .lbs) }
#Preview("8 · Weekly Range · lb") { lensPreview(.weeklyRange, .lbs) }
#Preview("9 · Weekly Loss · lb") { lensPreview(.weeklyLoss, .lbs) }

#Preview("Current Weight · dark · kg") { lensPreview(.currentWeight, .kg).preferredColorScheme(.dark) }
#Preview("Total Lost · dark · kg") { lensPreview(.totalLost, .kg).preferredColorScheme(.dark) }
#Preview("Pace · dark · kg") { lensPreview(.pace, .kg).preferredColorScheme(.dark) }
#Preview("Forecast · dark · kg") { lensPreview(.forecast, .kg).preferredColorScheme(.dark) }

#Preview("Carousel") {
    @Previewable @State var selection: TodayLens = .currentWeight
    return TodayLensCarousel(
        active: LensPreviewFixture.active,
        projection: LensPreviewFixture.projection,
        chart: LensPreviewFixture.chart,
        domains: LensPreviewFixture.domains,
        weekly: LensPreviewFixture.weekly,
        pace: LensPreviewFixture.pace,
        thisWeek: LensPreviewFixture.thisWeek,
        unit: .lbs,
        hasEntryToday: true,
        dayNumber: 81,
        selectedDate: LensPreviewFixture.asOf,
        selectedDayValue: 156.2,
        selectedDayLogged: true,
        selectedDayNumber: 81,
        lenses: TodayLens.allCases,
        onToggleUnit: {}, onLog: {}, onOpenDetail: {},
        selection: $selection
    )
}
#endif
