import SwiftUI

/// Converts the canonical analytics model into the three decision-oriented
/// Today views. This layer formats and converts units; it does not recalculate
/// trend, pace, plan, weekly buckets, or forecast semantics.
struct TodayLensBuilder {
    let active: ActiveCut
    let analytics: TodayAnalyticsModel
    let weekly: WeeklyCutChartModel
    let unit: WeightUnit
    let dayNumber: Int?
    var calendar: Calendar = .current

    private static let md: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    private func disp(_ lb: Double) -> Double { unit == .lbs ? lb : UnitConvert.lbToKg(lb) }
    private func dp(_ points: [DatedValue]) -> [DatedValue] {
        points.map { DatedValue(date: $0.date, value: disp($0.value)) }
    }
    private var sym: String { unit.symbol }
    private var dash: String { "—" }
    private func num(_ lb: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", disp(lb))
    }
    private func fmt(_ display: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", display)
    }
    private func dateStr(_ date: Date) -> String { Self.md.string(from: date) }

    private func rate(_ signedLbPerWeek: Double) -> String {
        let value = disp(abs(signedLbPerWeek))
        if signedLbPerWeek < -0.005 { return String(format: "↓%.1f", value) }
        if signedLbPerWeek > 0.005 { return String(format: "↑%.1f", value) }
        return "0.0"
    }

    private func lossRate(_ magnitudeLbPerWeek: Double) -> String {
        magnitudeLbPerWeek > 0.005 ? "↓\(num(magnitudeLbPerWeek))" : "0.0"
    }

    private func scrubModel(
        points: [DatedValue],
        heroUnit: String,
        value: (Int, DatedValue) -> String,
        context: (Int, DatedValue) -> String,
        secondary: (Int, DatedValue) -> String?
    ) -> LensScrubModel? {
        guard !points.isEmpty else { return nil }
        let info = points.enumerated().map { index, point in
            LensScrubInfo(
                heroValue: value(index, point),
                heroUnit: heroUnit,
                heroContext: context(index, point),
                secondary: secondary(index, point)
            )
        }
        let callouts = points.enumerated().map { value($0.offset, $0.element) + " · " + dateStr($0.element.date) }
        return LensScrubModel(points: points, info: info, callouts: callouts)
    }

    private let lineColor = Color.white
    private let lineHalo = TodayLens.depthNavy
    private let secondaryLine = Color.white.opacity(0.48)
    private let markerColor = Color.white.opacity(0.48)
    private let gridColor = Color.white.opacity(0.22)
    private let labelColor = Color.white.opacity(0.68)

    func render(_ lens: TodayLens) -> RenderedLens {
        switch lens {
        case .progress: progressLens()
        case .recentTrend: recentTrendLens()
        case .weeklySummary: weeklySummaryLens()
        }
    }

    // MARK: - Progress vs Plan

    private func progressLens() -> RenderedLens {
        let trend = analytics.currentTrend
        let heroValue = trend.map { num($0.value) } ?? dash
        let context: String? = trend.map {
            "7 calendar days · \(analytics.currentTrendObservationCount) readings · through \(dateStr($0.date))"
        }
        let xUpper = max(analytics.targetDate, analytics.asOfDate)
        let xDomain = analytics.startDate...max(analytics.startDate, xUpper)

        var values = analytics.observations.map(\.value)
            + analytics.trend.map(\.value)
            + [analytics.startWeightLb, analytics.targetWeightLb]
        if let forecast = analytics.forecast {
            values += [forecast.lowerTargetWeightLb, forecast.upperTargetWeightLb]
        }
        let yDomainLb = stableWeightDomain(values)
        let yDomain = disp(yDomainLb.lowerBound)...disp(yDomainLb.upperBound)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        spec.references = weightAxisReferences(yDomainLb)
        spec.references.append(
            .init(
                kind: .horizontal(disp(analytics.targetWeightLb)),
                color: Color.white.opacity(0.42),
                dash: [3, 4],
                label: "Target \(num(analytics.targetWeightLb)) \(sym)",
                labelColor: labelColor
            )
        )
        if xDomain.contains(analytics.asOfDate) {
            spec.references.append(
                .init(kind: .vertical(analytics.asOfDate), color: gridColor, dash: [2, 4], label: "Today", labelColor: labelColor)
            )
        }
        spec.series = [
            .init(points: dp(analytics.plannedTrajectory), color: secondaryLine, lineWidth: 1.5, dash: [4, 4], smooth: false),
            .init(points: dp(analytics.trend), color: lineColor, lineWidth: 2.8, smooth: false, haloColor: lineHalo),
        ]
        if let forecast = analytics.forecast {
            spec.bands = [
                .init(lower: dp(forecast.lowerLine), upper: dp(forecast.upperLine), color: .white, opacity: 0.12, smooth: false)
            ]
            spec.series.append(
                .init(points: dp(forecast.centerLine), color: Color.white.opacity(0.82), lineWidth: 2, dash: [5, 4], smooth: false)
            )
        }
        spec.markerSets = [.init(points: dp(analytics.observations), color: markerColor, radius: 2.2)]
        spec.maskBoundary = dp(analytics.trend)
        spec.maskBoundarySmooth = false
        if let trend {
            spec.endpoint = .init(
                point: DatedValue(date: trend.date, value: disp(trend.value)),
                color: .white,
                radius: 5,
                haloColor: TodayLens.progress.accent
            )
        }
        spec.dateLabels = [
            .init(date: analytics.startDate, text: dateStr(analytics.startDate), color: labelColor),
            .init(date: analytics.asOfDate, text: dateStr(analytics.asOfDate), color: labelColor),
            .init(date: analytics.targetDate, text: dateStr(analytics.targetDate), color: labelColor),
        ]

        let latest = analytics.latestObservation.map { "\(num($0.value)) · \(dateStr($0.date))" } ?? dash
        let planToday = "\(num(analytics.plannedWeightAsOfLb)) \(sym)"
        let forecastValue: String = {
            guard let forecast = analytics.forecast else { return dash }
            return "\(num(forecast.lowerTargetWeightLb))–\(num(forecast.upperTargetWeightLb))"
        }()
        let stats = [
            LensStat(label: "Latest", value: latest),
            LensStat(label: "Plan today", value: planToday),
            LensStat(label: "Forecast \(dateStr(analytics.targetDate))", value: forecastValue),
        ]
        let planComparison = analytics.trendMinusPlanLb.map {
            "Current trend is \(num(abs($0))) \(sym) \($0 >= 0 ? "above" : "below") today's plan."
        } ?? ""
        let a11y = "Progress versus plan. Current seven-calendar-day trend \(heroValue) \(sym). Latest observation \(latest). \(planComparison)"

        let currentDisplay = trend.map { disp($0.value) }
        let scrub = scrubModel(
            points: dp(analytics.observations),
            heroUnit: sym,
            value: { _, p in fmt(p.value) },
            context: { _, p in "Observed · \(dateStr(p.date))" },
            secondary: { _, p in
                guard let currentDisplay else { return nil }
                let delta = p.value - currentDisplay
                return String(format: "%+.1f %@ vs current trend", delta, sym)
            }
        )
        return RenderedLens(
            lens: .progress,
            heroValue: heroValue,
            heroUnit: sym,
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: a11y,
            scrub: scrub
        )
    }

    // MARK: - Recent Trend

    private func recentTrendLens() -> RenderedLens {
        let fit = analytics.recentPace
        let heroValue = fit.map { rate($0.signedLbPerWeek) } ?? dash
        let context: String? = fit.map {
            "14-day fit · \($0.observationCount) readings · \(dateStr($0.windowStart))–\(dateStr($0.windowEnd))"
        }
        let latestDate = analytics.latestObservation?.date ?? analytics.asOfDate
        let requestedLower = calendar.date(byAdding: .day, value: -29, to: latestDate) ?? latestDate
        let observations = analytics.observations.filter { $0.date >= requestedLower && $0.date <= latestDate }
        let trend = analytics.trend.filter { $0.date >= requestedLower && $0.date <= latestDate }
        let xLower = observations.first?.date ?? requestedLower
        let xDomain = xLower...max(xLower, latestDate)
        let recentValues = observations.map(\.value) + trend.map(\.value) + (fit?.fittedLine.map(\.value) ?? [])
        let yDomainLb = recentWeightDomain(recentValues)
        let yDomain = disp(yDomainLb.lowerBound)...disp(yDomainLb.upperBound)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: yDomain)
        spec.references = weightAxisReferences(yDomainLb)
        spec.markerSets = [.init(points: dp(observations), color: markerColor, radius: 2.6)]
        spec.series = [.init(points: dp(trend), color: lineColor, lineWidth: 2.8, smooth: false, haloColor: lineHalo)]
        if let fit {
            spec.series.append(
                .init(points: dp(fit.fittedLine), color: Color.white.opacity(0.70), lineWidth: 1.8, dash: [5, 4], smooth: false)
            )
        }
        spec.maskBoundary = dp(trend)
        spec.maskBoundarySmooth = false
        if let current = analytics.currentTrend {
            spec.endpoint = .init(
                point: DatedValue(date: current.date, value: disp(current.value)),
                color: .white,
                radius: 5,
                haloColor: TodayLens.recentTrend.accent
            )
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let needed: String = {
            switch analytics.neededNow {
            case .available(let value): return "\(lossRate(value)) \(sym)/wk"
            case .goalReached: return "Goal reached"
            case .deadlinePassed: return "Deadline passed"
            case .insufficientData: return dash
            }
        }()
        let stats = [
            LensStat(label: "Needed now", value: needed),
            LensStat(label: "Original plan", value: "\(lossRate(analytics.originalPlannedLossLbPerWeek)) \(sym)/wk"),
            LensStat(label: "Current trend", value: analytics.currentTrend.map { "\(num($0.value)) \(sym)" } ?? dash),
        ]
        let a11y = "Recent trend. \(fit.map { rate($0.signedLbPerWeek) + " " + sym + " per week over a 14-day fit" } ?? "Not enough data for a recent pace"). Needed now \(needed)."
        let scrub = scrubModel(
            points: dp(observations),
            heroUnit: sym,
            value: { _, p in fmt(p.value) },
            context: { _, p in "Observed · \(dateStr(p.date))" },
            secondary: { _, _ in fit.map { "14-day fit \(rate($0.signedLbPerWeek)) \(sym)/wk" } }
        )
        return RenderedLens(
            lens: .recentTrend,
            heroValue: heroValue,
            heroUnit: "\(sym)/week",
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: a11y,
            scrub: scrub
        )
    }

    // MARK: - Weekly Average + Range

    private func weeklySummaryLens() -> RenderedLens {
        let visible = Array(weekly.points.suffix(9))
        let current = visible.last
        let heroValue = current.map { num($0.averageWeight) } ?? dash
        let context = current.map {
            "Week of \(dateStr($0.weekStart))\($0.isWeekToDate ? " · WTD" : ($0.isPartial ? " · partial" : "")) · \($0.readingCount) readings"
        }
        let averages = visible.map { DatedValue(date: $0.weekStart, value: $0.averageWeight) }
        let extremes = visible.flatMap { [$0.minWeight, $0.maxWeight] }
        let yDomainLb = recentWeightDomain(extremes)
        let xLower = visible.first?.weekStart ?? analytics.startDate
        let xUpper = visible.last?.weekStart ?? xLower
        let xDomain = xLower...max(xLower, xUpper)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: disp(yDomainLb.lowerBound)...disp(yDomainLb.upperBound))
        spec.references = weightAxisReferences(yDomainLb)
        spec.whiskers = visible.map {
            .init(
                date: $0.weekStart,
                low: disp($0.minWeight),
                high: disp($0.maxWeight),
                color: Color.white.opacity(0.48),
                lineWidth: 1.4,
                capWidth: 8
            )
        }
        spec.series = [.init(points: dp(averages), color: lineColor, lineWidth: 2.8, smooth: false, haloColor: lineHalo)]
        spec.markerSets = [.init(points: dp(averages), color: Color.white.opacity(0.90), radius: 2.8)]
        spec.maskBoundary = dp(averages)
        spec.maskBoundarySmooth = false
        if let last = averages.last {
            spec.endpoint = .init(
                point: DatedValue(date: last.date, value: disp(last.value)),
                color: .white,
                radius: 5,
                haloColor: TodayLens.weeklySummary.accent
            )
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let range = current.map { "\(num($0.minWeight))–\(num($0.maxWeight))" } ?? dash
        let previous = current.flatMap { point -> Double? in
            guard let loss = point.lossVsPrevious else { return nil }
            return point.averageWeight + loss
        }
        let change = current?.lossVsPrevious.map { rate(-$0) } ?? dash
        let stats = [
            LensStat(label: "Observed range", value: range),
            LensStat(label: current?.isWeekToDate == true ? "Prior matched" : "Previous", value: previous.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "Mean change", value: change == dash ? dash : "\(change) \(sym)"),
        ]
        let a11y = "Weekly average and observed range. \(heroValue) \(sym). Observed range \(range) \(sym). \(current?.readingCount ?? 0) readings."
        let displayAverages = dp(averages)
        let scrub = scrubModel(
            points: displayAverages,
            heroUnit: sym,
            value: { _, p in fmt(p.value) },
            context: { index, p in
                "Week of \(dateStr(p.date))\(visible[index].isWeekToDate ? " · WTD" : "")"
            },
            secondary: { index, _ in
                let point = visible[index]
                return "observed \(num(point.minWeight))–\(num(point.maxWeight)) \(sym) · \(point.readingCount) readings"
            }
        )
        return RenderedLens(
            lens: .weeklySummary,
            heroValue: heroValue,
            heroUnit: sym,
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: a11y,
            scrub: scrub
        )
    }

    // MARK: - Domains and axes

    private func stableWeightDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...10 }
        let midpoint = (low + high) / 2
        let span = max(10, high - low + 4)
        let lower = floor((midpoint - span / 2) / 2) * 2
        let upper = ceil((midpoint + span / 2) / 2) * 2
        return lower...max(lower + 10, upper)
    }

    private func recentWeightDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...8 }
        let midpoint = (low + high) / 2
        let span = max(8, high - low + 3)
        let lower = floor((midpoint - span / 2) / 2) * 2
        let upper = ceil((midpoint + span / 2) / 2) * 2
        return lower...max(lower + 8, upper)
    }

    private func weightAxisReferences(_ domainLb: ClosedRange<Double>) -> [LensPlotSpec.Reference] {
        let span = domainLb.upperBound - domainLb.lowerBound
        let steps = span >= 18 ? 4 : 2
        return (0...steps).map { index in
            let value = domainLb.lowerBound + span * Double(index) / Double(steps)
            return .init(
                kind: .horizontal(disp(value)),
                color: gridColor,
                dash: nil,
                lineWidth: 0.7,
                label: index == steps ? "\(num(value, decimals: 0)) \(sym)" : num(value, decimals: 0),
                labelColor: labelColor
            )
        }
    }

    private func evenlySpacedDateLabels(_ xDomain: ClosedRange<Date>) -> [LensPlotSpec.DateLabel] {
        let lower = xDomain.lowerBound
        let upper = xDomain.upperBound
        let mid = lower.addingTimeInterval(upper.timeIntervalSince(lower) / 2)
        return [lower, mid, upper].map { .init(date: $0, text: dateStr($0), color: labelColor) }
    }
}
