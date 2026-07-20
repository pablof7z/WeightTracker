import SwiftUI

/// Turns the canonical shared models into a `RenderedLens` for each of the six
/// lenses. All model weights are canonical pounds; this is the single place
/// that converts to the display unit and formats strings. Chart geometry is
/// expressed in the same display unit as the hero so line and value always
/// agree.
struct TodayLensBuilder {
    let active: ActiveCut
    let projection: CutProjectionResult
    let chart: CutChartModel
    let domains: CutChartDomainState
    let weekly: WeeklyCutChartModel
    let pace: PaceLensModel
    let thisWeek: ThisWeekModel
    let unit: WeightUnit
    let dayNumber: Int?
    var calendar: Calendar = .current

    private static let md: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d"); return f
    }()

    // MARK: Unit + formatting helpers

    /// Convert a canonical-pound value (absolute weight or a delta/rate) to the
    /// display unit. `lbToKg` is a pure scale, so it converts deltas and rates
    /// correctly too.
    private func disp(_ lb: Double) -> Double { unit == .lbs ? lb : UnitConvert.lbToKg(lb) }
    private func dp(_ points: [DatedValue]) -> [DatedValue] {
        points.map { DatedValue(date: $0.date, value: disp($0.value)) }
    }
    private var sym: String { unit.symbol }
    private func num(_ lb: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", disp(lb))
    }
    private func signed(_ lb: Double, decimals: Int = 1) -> String {
        String(format: "%+.\(decimals)f", disp(lb))
    }
    private func dateStr(_ d: Date) -> String { Self.md.string(from: d) }
    private var dash: String { "—" }

    // Scrub points arrive already converted to the display unit (they are the
    // very points the plot draws), so they format without a second conversion.
    private func fmt(_ display: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", display)
    }
    private func fmtSigned(_ display: Double, decimals: Int = 1) -> String {
        String(format: "%+.\(decimals)f", display)
    }

    /// 1-based cut day for a date, or nil before the cut started.
    private func cutDay(_ d: Date) -> Int? {
        let start = calendar.startOfDay(for: active.startDate)
        let day = calendar.startOfDay(for: d)
        guard day >= start else { return nil }
        return (calendar.dateComponents([.day], from: start, to: day).day ?? 0) + 1
    }

    /// Assembles the parallel scrub arrays from one display-unit series.
    private func scrubModel(
        points: [DatedValue],
        heroUnit: String,
        value: (Int, DatedValue) -> String,
        context: (Int, DatedValue) -> String,
        secondary: (Int, DatedValue) -> String?
    ) -> LensScrubModel? {
        guard !points.isEmpty else { return nil }
        var info: [LensScrubInfo] = []
        var callouts: [String] = []
        for (i, p) in points.enumerated() {
            let v = value(i, p)
            info.append(LensScrubInfo(heroValue: v, heroUnit: heroUnit, heroContext: context(i, p), secondary: secondary(i, p)))
            callouts.append("\(v) · \(dateStr(p.date))")
        }
        return LensScrubModel(points: points, info: info, callouts: callouts)
    }

    // MARK: Canvas palette
    //
    // The line, its glow fill, markers, and endpoint live over the continuous
    // atmospheric depth gradient, so the dominant signal is drawn white with a
    // dark halo (legible over both the pale top and the navy floor). The lens
    // accent expresses itself through the background gradient, not the line.
    private let lineColor = Color.white
    private let lineHalo = TodayLens.depthNavy
    private let trendColor = Color.white.opacity(0.30)
    private let markerColor = Color.white.opacity(0.28)
    private let fillColor = Color.white
    private let labelColor = Color.white.opacity(0.62)
    private let gridColor = Color.white.opacity(0.26)
    private let endpointColor = Color.white

    // MARK: Dispatch

    func render(_ lens: TodayLens) -> RenderedLens {
        switch lens {
        case .currentWeight: return currentWeight()
        case .totalLost:     return totalLost()
        case .thisWeek:      return thisWeekLens()
        case .weeklyAverage: return weeklyAverageLens()
        case .pace:          return paceLens()
        case .forecast:      return forecastLens()
        case .fullCut:       return fullCutLens()
        case .weeklyRange:   return weeklyRangeLens()
        case .weeklyLoss:    return weeklyLossLens()
        }
    }

    // MARK: 1 — Current Weight

    private func currentWeight() -> RenderedLens {
        let accent = TodayLens.currentWeight.accent
        let raw = chart.raw
        let latest = raw.last

        let heroValue = latest.map { num($0.value) } ?? dash
        var context: String? = nil
        if let latest {
            context = dateStr(latest.date)
            if let dayNumber { context! += " · Day \(dayNumber)" }
        }

        // ~30-day rolling window of observed data. The domain is clamped to the
        // first and last readings actually in the window so the line spans the
        // full width edge-to-edge (no forward tail — projection lives in the
        // Forecast lens).
        let anchorX = raw.last?.date ?? chart.forecastAnchor.date
        let windowStart = calendar.date(byAdding: .day, value: -30, to: anchorX) ?? anchorX
        let inWindow = raw.filter { $0.date >= windowStart && $0.date <= anchorX }
        let xLower = inWindow.first?.date ?? windowStart
        let xUpper = inWindow.last?.date ?? anchorX
        let xDomain = xLower...max(xLower, xUpper)
        let half = domains.recentSpan / 2
        let yDomain = disp(domains.recentCenter - half)...disp(domains.recentCenter + half)

        let rawInDomain = dp(inWindow)
        let trendInDomain = dp(chart.trailing7.filter { $0.date >= xLower && $0.date <= xUpper })

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        spec.fills = [.init(points: rawInDomain, baseline: .plotBottom, color: fillColor, topOpacity: 0.20)]
        // Observed data only — one dominant white line with a trailing trend as
        // the quiet secondary. Projection lives in the Forecast lens.
        spec.series = [
            .init(points: trendInDomain, color: trendColor, lineWidth: 1.6, smooth: true),
            .init(points: rawInDomain, color: lineColor, lineWidth: 2.6, smooth: true, haloColor: lineHalo),
        ]
        spec.markerSets = [.init(points: rawInDomain, color: markerColor, radius: 2)]
        if let last = rawInDomain.last {
            spec.endpoint = .init(point: last, color: endpointColor, radius: 5, haloColor: accent)
        }
        if let target = latestWithinTargetLine(yDomain: yDomain) {
            spec.references = [target]
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let stats = [
            LensStat(label: "7-day avg", value: chart.trailing7.last.map { "\(num($0.value)) \(sym)" } ?? dash),
            LensStat(label: "This week", value: thisWeek.headline.map { "\(signed($0)) \(sym)" } ?? dash),
            LensStat(label: "Projection", value: pace.projectedTargetWeightLb.map { "\(num($0)) \(sym)" } ?? dash),
        ]
        let a11y = "Current weight. \(heroValue) \(sym)\(context.map { ", \($0)" } ?? ""). "
            + stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + "."

        // Inspect the raw daily line. The useful comparison is the hovered
        // weigh-in against the most recent one.
        let latestDisplay = rawInDomain.last?.value
        let scrub = scrubModel(
            points: rawInDomain,
            heroUnit: sym,
            value: { _, p in fmt(p.value) },
            context: { _, p in
                let d = dateStr(p.date)
                return cutDay(p.date).map { "\(d) · Day \($0)" } ?? d
            },
            secondary: { i, p in
                guard let latestDisplay else { return nil }
                if i == rawInDomain.count - 1 { return "Latest reading" }
                return "vs today \(fmtSigned(p.value - latestDisplay)) \(sym)"
            }
        )
        return RenderedLens(lens: .currentWeight, heroValue: heroValue, heroUnit: sym, heroContext: context, stats: stats, plot: spec, accessibilitySummary: a11y, scrub: scrub)
    }

    private func latestWithinTargetLine(yDomain: ClosedRange<Double>) -> LensPlotSpec.Reference? {
        let t = disp(chart.targetWeightLb)
        guard yDomain.contains(t) else { return nil }
        return .init(kind: .horizontal(t), color: gridColor, dash: [2, 5], label: "Target", labelColor: labelColor)
    }

    // MARK: 2 — Total Lost

    private func totalLost() -> RenderedLens {
        let accent = TodayLens.totalLost.accent
        let latest = chart.raw.last
        let lostLb = latest.map { chart.startWeightLb - $0.value }
        let goalLossLb = chart.startWeightLb - chart.targetWeightLb

        let heroValue = lostLb.map { num($0) } ?? dash
        let context = "Since \(dateStr(chart.startDate))"

        let cum = chart.raw.map { DatedValue(date: $0.date, value: chart.startWeightLb - $0.value) }
        let cumD = dp(cum)
        let cumValues = cum.map(\.value)
        let lowerLb = min(-2, (cumValues.min() ?? 0) - 1)
        let upperLb = max(goalLossLb + 2, (cumValues.max() ?? goalLossLb) + 2)
        let xDomain = chart.startDate...chart.targetDate
        let yDomain = disp(lowerLb)...disp(upperLb)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        spec.fills = [.init(points: cumD, baseline: .value(0), color: fillColor, topOpacity: 0.20)]
        spec.references = [
            .init(kind: .horizontal(0), color: gridColor, dash: [2, 4]),
            .init(kind: .horizontal(disp(goalLossLb)), color: gridColor, dash: [2, 5], label: "Goal", labelColor: labelColor),
        ]
        spec.series = [.init(points: cumD, color: lineColor, lineWidth: 2.6, smooth: true, haloColor: lineHalo)]
        spec.markerSets = [.init(points: cumD, color: markerColor, radius: 1.8)]
        if let last = cumD.last {
            spec.endpoint = .init(point: last, color: endpointColor, radius: 5, haloColor: accent)
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let stats = [
            LensStat(label: "Start", value: "\(num(chart.startWeightLb)) \(sym)"),
            LensStat(label: "Current", value: latest.map { "\(num($0.value)) \(sym)" } ?? dash),
            LensStat(label: "Target", value: "\(num(chart.targetWeightLb)) \(sym)"),
        ]
        let a11y = "Total lost. \(heroValue) \(sym) lost, \(context). "
            + stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + "."

        // Inspect the cumulative-loss line. Progress toward the goal loss is the
        // most useful reading at any past point.
        let goalLossDisplay = disp(goalLossLb)
        let scrub = scrubModel(
            points: cumD,
            heroUnit: "\(sym) lost",
            value: { _, p in fmt(p.value) },
            context: { _, p in dateStr(p.date) },
            secondary: { _, p in
                guard goalLossDisplay > 0 else { return nil }
                let pct = max(0, p.value / goalLossDisplay * 100)
                return "\(Int(pct.rounded()))% of goal"
            }
        )
        return RenderedLens(lens: .totalLost, heroValue: heroValue, heroUnit: "\(sym) lost", heroContext: context, stats: stats, plot: spec, accessibilitySummary: a11y, scrub: scrub)
    }

    // MARK: 3 — This Week

    private func thisWeekLens() -> RenderedLens {
        let accent = TodayLens.thisWeek.accent
        let heroValue = thisWeek.headline.map { signed($0) } ?? dash
        var context = "\(dateStr(thisWeek.weekStart)) – \(dateStr(thisWeek.weekEnd))"
        if thisWeek.isPartial { context += " · partial" }

        let pts = dp(thisWeek.points)
        let xDomain = thisWeek.weekStart...thisWeek.weekEnd
        let yDomain = disp(thisWeek.yDomain.lowerBound)...disp(thisWeek.yDomain.upperBound)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        spec.references = [.init(kind: .horizontal(0), color: gridColor, dash: [2, 4], label: nil)]
        if pts.count >= 2 {
            spec.fills = [.init(points: pts, baseline: .value(0), color: fillColor, topOpacity: 0.20)]
            spec.series = [.init(points: pts, color: lineColor, lineWidth: 2.6, smooth: true, haloColor: lineHalo)]
        }
        spec.markerSets = [.init(points: pts, color: markerColor, radius: 2.6)]
        if let last = pts.last {
            spec.endpoint = .init(point: last, color: endpointColor, radius: 5, haloColor: accent)
        }
        spec.dateLabels = [
            .init(date: thisWeek.weekStart, text: dateStr(thisWeek.weekStart), color: labelColor),
            .init(date: thisWeek.weekEnd, text: dateStr(thisWeek.weekEnd), color: labelColor),
        ]

        let stats = [
            LensStat(label: "Avg/day", value: thisWeek.avgPerDay.map { "\(signed($0, decimals: 2)) \(sym)" } ?? dash),
            LensStat(label: "Week avg", value: thisWeek.weekAverageLb.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "Logged", value: "\(thisWeek.daysLogged) of 7"),
        ]
        let a11y = "This week. \(heroValue) \(sym) this week, \(context). "
            + stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + "."

        // Inspect the in-week cumulative change. The line is a delta, so the
        // most useful companion is the actual weight logged that day.
        let baselineDisplay = thisWeek.baselineLb.map { disp($0) }
        let scrub = scrubModel(
            points: pts,
            heroUnit: "\(sym) this week",
            value: { _, p in fmtSigned(p.value) },
            context: { _, p in dateStr(p.date) },
            secondary: { _, p in
                guard let baselineDisplay else { return nil }
                return "weighed \(fmt(baselineDisplay + p.value)) \(sym)"
            }
        )
        return RenderedLens(lens: .thisWeek, heroValue: heroValue, heroUnit: "\(sym) this week", heroContext: context, stats: stats, plot: spec, accessibilitySummary: a11y, scrub: scrub)
    }

    // MARK: 4 — Weekly Average

    private func weeklyAverageLens() -> RenderedLens {
        let accent = TodayLens.weeklyAverage.accent
        let visible = Array(weekly.points.suffix(9))
        let current = visible.last

        let heroValue = current.map { num($0.averageWeight) } ?? dash
        let context = current.map { $0.isWeekToDate ? "Week to date" : "Last full week" }

        let avgPoints = visible.map { DatedValue(date: $0.weekStart, value: $0.averageWeight) }
        let avgD = dp(avgPoints)
        let values = visible.map { disp($0.averageWeight) }
        let lo = (values.min() ?? 0) - 0.8
        let hi = (values.max() ?? 1) + 0.8
        // No horizontal padding: the first and last weekly points sit on the
        // screen edges so the line spans the full width.
        let xLower = visible.first?.weekStart ?? Date()
        let xUpper = visible.last?.weekStart ?? Date()
        let xDomain = xLower...max(xLower, xUpper)
        let yDomain = lo...max(lo + 1, hi)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        spec.fills = [.init(points: avgD, baseline: .plotBottom, color: fillColor, topOpacity: 0.18)]
        spec.series = [.init(points: avgD, color: lineColor, lineWidth: 2.6, smooth: true, haloColor: lineHalo)]
        // Completed weeks are filled dots; the current week-to-date point is the
        // distinct outlined endpoint.
        let completed = visible.filter { !$0.isWeekToDate }.map { DatedValue(date: $0.weekStart, value: $0.averageWeight) }
        spec.markerSets = [.init(points: dp(completed), color: markerColor, radius: 2.8)]
        if let last = avgD.last {
            spec.endpoint = .init(point: last, color: endpointColor, radius: 5, haloColor: accent)
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        // Change vs the matched previous comparable period.
        let loss = current?.lossVsPrevious // positive == lost
        let previous: Double? = {
            guard let current, let loss else { return nil }
            return current.averageWeight + loss
        }()
        // Change of the average itself: current − previous == −loss (a fall in
        // the average is a negative change).
        let changeStat = loss.map { "\(signed(-$0)) \(sym)" } ?? dash
        let readingsStat = current.map { "\($0.readingCount)\($0.isWeekToDate ? " WTD" : "")" } ?? dash

        let stats = [
            LensStat(label: "Previous", value: previous.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "Change", value: changeStat),
            LensStat(label: "Readings", value: readingsStat),
        ]
        let a11y = "Weekly average. \(heroValue) \(sym)\(context.map { ", \($0)" } ?? ""). "
            + stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + "."

        // Inspect the weekly-average line. `visible` is parallel to `avgD`, so
        // each point can report that week's change against the prior week.
        let scrub = scrubModel(
            points: avgD,
            heroUnit: sym,
            value: { _, p in fmt(p.value) },
            context: { i, p in
                let label = "Wk of \(dateStr(p.date))"
                return visible[i].isWeekToDate ? "\(label) · to date" : label
            },
            secondary: { i, _ in
                guard let loss = visible[i].lossVsPrevious else { return "First week" }
                // A fall in the average is a negative change.
                return "\(fmtSigned(disp(-loss))) \(sym) vs prev"
            }
        )
        return RenderedLens(lens: .weeklyAverage, heroValue: heroValue, heroUnit: sym, heroContext: context, stats: stats, plot: spec, accessibilitySummary: a11y, scrub: scrub)
    }

    // MARK: 5 — Pace

    private func paceLens() -> RenderedLens {
        let accent = TodayLens.pace.accent
        let heroValue = pace.latest.map { num($0) } ?? dash
        let context = "\(pace.windowDays)-day pace"

        let actualRaw = pace.actual.filter { pace.xDomain.contains($0.date) }
        // Clamp the domain to the first/last actual pace point so the rate line
        // spans the full width edge-to-edge.
        let xLower = actualRaw.first?.date ?? pace.xDomain.lowerBound
        let xUpper = actualRaw.last?.date ?? pace.xDomain.upperBound
        let xDomain = xLower...max(xLower, xUpper)
        let actualInDomain = dp(actualRaw)
        let yDomain = disp(pace.yDomain.lowerBound)...disp(pace.yDomain.upperBound)
        let requiredNowD = disp(pace.requiredNow)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        // The meaningful shaded region is the gap between actual and required.
        if actualInDomain.count >= 2 {
            spec.fills = [.init(points: actualInDomain, baseline: .value(requiredNowD), color: fillColor, topOpacity: 0.16)]
        }
        spec.references = [
            .init(kind: .horizontal(0), color: gridColor, dash: [2, 4]),
            .init(kind: .horizontal(requiredNowD), color: gridColor, dash: [4, 3], label: "Required", labelColor: labelColor),
        ]
        spec.series = [.init(points: actualInDomain, color: lineColor, lineWidth: 2.6, smooth: true, haloColor: lineHalo)]
        if let last = actualInDomain.last {
            spec.endpoint = .init(point: last, color: endpointColor, radius: 5, haloColor: accent)
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let stats = [
            LensStat(label: "Required", value: "\(num(pace.requiredNow)) \(sym)/wk"),
            LensStat(label: "Vs required", value: pace.vsRequired.map { "\(signed($0)) \(sym)/wk" } ?? dash),
            LensStat(label: "Projection", value: pace.projectedTargetWeightLb.map { "\(num($0)) \(sym)" } ?? dash),
        ]
        let a11y = "Pace. \(heroValue) \(sym) per week, \(context). "
            + stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + "."

        // Inspect the actual-pace line. The gap to the rate currently required
        // is the whole point of this lens, so it is the secondary readout.
        let scrub = scrubModel(
            points: actualInDomain,
            heroUnit: "\(sym)/week",
            value: { _, p in fmt(p.value) },
            context: { _, p in dateStr(p.date) },
            secondary: { _, p in "vs required \(fmtSigned(p.value - requiredNowD)) \(sym)/wk" }
        )
        return RenderedLens(lens: .pace, heroValue: heroValue, heroUnit: "\(sym)/week", heroContext: context, stats: stats, plot: spec, accessibilitySummary: a11y, scrub: scrub)
    }

    // MARK: 6 — Forecast

    private func forecastLens() -> RenderedLens {
        let accent = TodayLens.forecast.accent
        let projected = projection.avgPath.last.map { UnitConvert.kgToLb($0.1) }
        let heroValue = projected.map { num($0) } ?? dash
        let context = dateStr(chart.targetDate)

        let xUpper = chart.targetDate
        let windowStart = calendar.date(byAdding: .day, value: -60, to: xUpper) ?? xUpper
        let anchor = chart.forecastAnchor
        let history = chart.trailing7.filter { $0.date >= windowStart && $0.date <= anchor.date }
        // Start the domain at the first history point so the observed line
        // reaches the left edge; the target date remains the right edge.
        let xLower = history.first?.date ?? windowStart
        let xDomain = xLower...max(xLower, xUpper)
        let typical = chart.typicalForecast.filter { xDomain.contains($0.date) }
        let best = chart.bestForecast
        let worst = chart.worstForecast

        // Band from best/worst (each anchored, so it is zero-width at the anchor).
        var lower: [DatedValue] = []
        var upper: [DatedValue] = []
        if best.count == worst.count, best.count >= 2 {
            for (b, w) in zip(best, worst) {
                lower.append(DatedValue(date: b.date, value: min(b.value, w.value)))
                upper.append(DatedValue(date: b.date, value: max(b.value, w.value)))
            }
        }

        // y-domain from everything visible.
        var yValues = (history + typical + [anchor]).map(\.value) + lower.map(\.value) + upper.map(\.value)
        yValues.append(chart.targetWeightLb)
        let yLo = (yValues.min() ?? chart.targetWeightLb) - 1.5
        let yHi = (yValues.max() ?? chart.startWeightLb) + 1.5
        let yDomain = disp(yLo)...disp(max(yLo + 1, yHi))

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        if !lower.isEmpty {
            spec.bands = [.init(lower: dp(lower), upper: dp(upper), color: fillColor, opacity: 0.12)]
        }
        // Per spec, the Forecast lens shades only the band between the lower and
        // upper bounds — no history area fill — so the uncertainty reads as
        // beginning now, not at the start of the cut. Observed history is the
        // quiet secondary; the typical projection (dashed) is the headline.
        if history.count >= 2 {
            spec.series.append(.init(points: dp(history), color: trendColor, lineWidth: 2, smooth: true))
        }
        if typical.count >= 2 {
            spec.series.append(.init(points: dp(typical), color: lineColor, lineWidth: 2.4, dash: [5, 4], smooth: true, haloColor: lineHalo))
        }
        spec.references = [.init(kind: .horizontal(disp(chart.targetWeightLb)), color: gridColor, dash: [2, 5], label: "Target", labelColor: labelColor)]
        spec.endpoint = .init(point: DatedValue(date: anchor.date, value: disp(anchor.value)), color: endpointColor, radius: 5, haloColor: accent)
        spec.dateLabels = [
            .init(date: xLower, text: dateStr(xLower), color: labelColor),
            .init(date: anchor.date, text: dateStr(anchor.date), color: labelColor),
            .init(date: xUpper, text: dateStr(xUpper), color: labelColor),
        ]

        let interval: String = {
            guard let lo = projection.worstEndKg, let hi = projection.bestEndKg else { return dash }
            let a = UnitConvert.kgToLb(min(lo, hi)), b = UnitConvert.kgToLb(max(lo, hi))
            return "\(num(a))–\(num(b))"
        }()
        let daysRemaining = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: chart.targetDate).day ?? 0)

        let stats = [
            LensStat(label: "Target", value: "\(num(chart.targetWeightLb)) \(sym)"),
            LensStat(label: "Interval", value: interval),
            LensStat(label: "Remaining", value: "\(daysRemaining)d"),
        ]
        let a11y = "Forecast. Typical projection \(heroValue) \(sym) on \(context). "
            + stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + "."

        // Inspect observed history, then the typical projection — one continuous
        // left-to-right series across the anchor, deduped where they meet.
        let combined = dp(history) + dp(typical.filter { $0.date > anchor.date })
        let targetDisplay = disp(chart.targetWeightLb)
        let scrub = scrubModel(
            points: combined,
            heroUnit: sym,
            value: { _, p in fmt(p.value) },
            context: { _, p in
                let d = dateStr(p.date)
                return p.date > anchor.date ? "\(d) · projected" : "\(d) · observed"
            },
            secondary: { _, p in "\(fmtSigned(p.value - targetDisplay)) \(sym) vs target" }
        )
        return RenderedLens(lens: .forecast, heroValue: heroValue, heroUnit: sym, heroContext: context, stats: stats, plot: spec, accessibilitySummary: a11y, scrub: scrub)
    }

    // MARK: 7 — Full Cut

    /// Absolute weight across the *whole* cut, start date to target date. The
    /// same observed series Current Weight shows, but never windowed — so the
    /// entire arc, and how much of the timeline is left, are both visible.
    private func fullCutLens() -> RenderedLens {
        let accent = TodayLens.fullCut.accent
        let raw = chart.raw
        let latest = raw.last

        let heroValue = latest.map { num($0.value) } ?? dash
        var context: String? = "\(dateStr(chart.startDate)) – \(dateStr(chart.targetDate))"
        if let dayNumber { context! += " · Day \(dayNumber)" }

        // The fixed plan timeline is the point of this lens, so the domain is
        // the cut itself rather than the data's extent.
        let xDomain = chart.startDate...max(chart.startDate, chart.targetDate)
        let yDomain = disp(domains.absoluteLower)...disp(max(domains.absoluteLower + 1, domains.absoluteUpper))

        let rawD = dp(raw)
        let trendD = dp(chart.trailing7)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        spec.fills = [.init(points: rawD, baseline: .plotBottom, color: fillColor, topOpacity: 0.18)]
        spec.references = [
            .init(kind: .horizontal(disp(chart.targetWeightLb)), color: gridColor, dash: [2, 5], label: "Target", labelColor: labelColor)
        ]
        spec.series = [
            .init(points: trendD, color: trendColor, lineWidth: 1.6, smooth: true),
            .init(points: rawD, color: lineColor, lineWidth: 2.6, smooth: true, haloColor: lineHalo),
        ]
        spec.markerSets = [.init(points: rawD, color: markerColor, radius: 1.6)]
        if let last = rawD.last {
            spec.endpoint = .init(point: last, color: endpointColor, radius: 5, haloColor: accent)
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let lostLb = latest.map { chart.startWeightLb - $0.value }
        let stats = [
            LensStat(label: "Start", value: "\(num(chart.startWeightLb)) \(sym)"),
            LensStat(label: "Lost", value: lostLb.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "Target", value: "\(num(chart.targetWeightLb)) \(sym)"),
        ]
        let a11y = "Full cut. \(heroValue) \(sym)\(context.map { ", \($0)" } ?? ""). "
            + stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + "."

        // Over the whole cut, the useful per-point reading is how far that day
        // sat from the target.
        let targetDisplay = disp(chart.targetWeightLb)
        let scrub = scrubModel(
            points: rawD,
            heroUnit: sym,
            value: { _, p in fmt(p.value) },
            context: { _, p in
                let d = dateStr(p.date)
                return cutDay(p.date).map { "\(d) · Day \($0)" } ?? d
            },
            secondary: { _, p in "\(fmtSigned(p.value - targetDisplay)) \(sym) vs target" }
        )
        return RenderedLens(lens: .fullCut, heroValue: heroValue, heroUnit: sym, heroContext: context, stats: stats, plot: spec, accessibilitySummary: a11y, scrub: scrub)
    }

    // MARK: 8 — Weekly Range

    /// The weekly-average line with each week's observed minimum and maximum as
    /// a whisker, so day-to-day scatter is visible without letting it dominate
    /// the trend.
    private func weeklyRangeLens() -> RenderedLens {
        let accent = TodayLens.weeklyRange.accent
        let visible = Array(weekly.points.suffix(9))
        let current = visible.last

        let heroValue = current.map { num($0.averageWeight) } ?? dash
        let context = current.map { $0.isWeekToDate ? "Week to date · with range" : "Last full week · with range" }

        let avgD = dp(visible.map { DatedValue(date: $0.weekStart, value: $0.averageWeight) })
        // The domain must contain the whiskers, not just the averages.
        let extremes = visible.flatMap { [disp($0.minWeight), disp($0.maxWeight)] }
        let lo = (extremes.min() ?? 0) - 0.6
        let hi = (extremes.max() ?? 1) + 0.6
        let xLower = visible.first?.weekStart ?? Date()
        let xUpper = visible.last?.weekStart ?? Date()
        let xDomain = xLower...max(xLower, xUpper)
        let yDomain = lo...max(lo + 1, hi)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        spec.whiskers = visible.map {
            .init(
                date: $0.weekStart,
                low: disp($0.minWeight),
                high: disp($0.maxWeight),
                color: .white.opacity(0.42),
                lineWidth: 1.4,
                capWidth: 8
            )
        }
        spec.series = [.init(points: avgD, color: lineColor, lineWidth: 2.6, smooth: true, haloColor: lineHalo)]
        spec.markerSets = [.init(points: avgD, color: .white.opacity(0.85), radius: 2.6)]
        if let last = avgD.last {
            spec.endpoint = .init(point: last, color: endpointColor, radius: 5, haloColor: accent)
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let rangeStat = current.map { "\(num($0.minWeight))–\(num($0.maxWeight))" } ?? dash
        let previous: Double? = {
            guard let current, let loss = current.lossVsPrevious else { return nil }
            return current.averageWeight + loss
        }()
        let stats = [
            LensStat(label: "Range", value: rangeStat),
            LensStat(label: "Previous", value: previous.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "Readings", value: current.map { "\($0.readingCount)\($0.isWeekToDate ? " WTD" : "")" } ?? dash),
        ]
        let a11y = "Weekly range. \(heroValue) \(sym) average\(context.map { ", \($0)" } ?? ""). "
            + stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + "."

        // `visible` is parallel to `avgD`, so each hovered week reports its own
        // spread — the thing the whiskers draw.
        let scrub = scrubModel(
            points: avgD,
            heroUnit: sym,
            value: { _, p in fmt(p.value) },
            context: { i, p in
                let label = "Wk of \(dateStr(p.date))"
                return visible[i].isWeekToDate ? "\(label) · to date" : label
            },
            secondary: { i, _ in
                let w = visible[i]
                return "range \(num(w.minWeight))–\(num(w.maxWeight)) \(sym)"
            }
        )
        return RenderedLens(lens: .weeklyRange, heroValue: heroValue, heroUnit: sym, heroContext: context, stats: stats, plot: spec, accessibilitySummary: a11y, scrub: scrub)
    }

    // MARK: 9 — Weekly Loss vs Required

    /// Week-over-week change as bars from a zero baseline against the plan's
    /// required weekly rate. Bars rather than a line: the quantity is discrete
    /// per week, and the form gives the carousel visual variety.
    private func weeklyLossLens() -> RenderedLens {
        // Only weeks with a genuinely comparable prior week produce a bar.
        let comparable = weekly.points.filter { $0.lossVsPrevious != nil }.suffix(9)
        let bars = comparable.map { DatedValue(date: $0.weekStart, value: $0.lossVsPrevious ?? 0) }
        let latest = bars.last

        let heroValue = latest.map { signed($0.value) } ?? dash
        let context = latest.map { "Wk of \(dateStr($0.date)) vs previous" } ?? "No comparable week yet"

        let barsD = dp(Array(bars))
        let requiredD = disp(weekly.requiredWeeklyLoss)
        // Zero must stay on the axis (it is the baseline), but the domain is
        // otherwise fitted to the data rather than forced symmetric — with all
        // weeks losing, a symmetric range would leave the bottom half empty.
        let values = barsD.map(\.value) + [requiredD, 0]
        let rawLo = min(0, values.min() ?? 0)
        let rawHi = max(0, values.max() ?? 1)
        let yPad = max(0.25, (rawHi - rawLo) * 0.14)
        let lo = rawLo < 0 ? rawLo - yPad : 0
        let hi = rawHi > 0 ? rawHi + yPad : 0
        let yDomain = lo...max(lo + 0.5, hi)
        // Bars are centered on their week, so the domain is padded by half a
        // week each side rather than clamped — otherwise the edge bars clip.
        let firstDate = barsD.first?.date ?? Date()
        let lastDate = barsD.last?.date ?? firstDate
        let pad: TimeInterval = 3.5 * 86_400
        let xDomain = firstDate.addingTimeInterval(-pad)...max(firstDate.addingTimeInterval(-pad), lastDate.addingTimeInterval(pad))

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        spec.bars = [.init(points: barsD, baseline: 0, color: .white, width: 18, opacity: 0.82)]
        spec.references = [
            .init(kind: .horizontal(0), color: gridColor, dash: [2, 4]),
            .init(kind: .horizontal(requiredD), color: gridColor, dash: [4, 3], label: "Required", labelColor: labelColor),
        ]
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let vsRequired = latest.map { $0.value - weekly.requiredWeeklyLoss }
        let stats = [
            LensStat(label: "Required", value: "\(num(weekly.requiredWeeklyLoss)) \(sym)/wk"),
            LensStat(label: "Vs required", value: vsRequired.map { "\(signed($0)) \(sym)/wk" } ?? dash),
            LensStat(label: "Weeks", value: "\(barsD.count)"),
        ]
        let a11y = "Weekly loss versus required. \(heroValue) \(sym) \(context). "
            + stats.map { "\($0.label) \($0.value)" }.joined(separator: ", ") + "."

        // Inspecting a bar reports that week's gap to the required rate — the
        // comparison the reference line makes visually.
        let scrub = scrubModel(
            points: barsD,
            heroUnit: "\(sym)/wk",
            value: { _, p in fmtSigned(p.value) },
            context: { _, p in "Wk of \(dateStr(p.date))" },
            secondary: { _, p in "vs required \(fmtSigned(p.value - requiredD)) \(sym)" }
        )
        return RenderedLens(lens: .weeklyLoss, heroValue: heroValue, heroUnit: "\(sym)/wk", heroContext: context, stats: stats, plot: spec, accessibilitySummary: a11y, scrub: scrub)
    }

    // MARK: Shared

    /// Two or three contextual date labels rendered inside the canvas.
    private func evenlySpacedDateLabels(_ xDomain: ClosedRange<Date>) -> [LensPlotSpec.DateLabel] {
        let lower = xDomain.lowerBound
        let upper = xDomain.upperBound
        let mid = lower.addingTimeInterval(upper.timeIntervalSince(lower) / 2)
        return [lower, mid, upper].map { .init(date: $0, text: dateStr($0), color: labelColor) }
    }
}
