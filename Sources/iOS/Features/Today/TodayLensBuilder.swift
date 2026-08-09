import SwiftUI

/// Converts the canonical analytics model into the Today chart collection.
/// Restored views are focused presentations of the same observations, trend,
/// plan, weekly buckets, and fitted forecast rather than alternate data stores.
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

    private func firstValueLabel(_ points: [DatedValue], suffix: String = "") -> [LensPlotSpec.PointLabel] {
        guard let first = points.first else { return [] }
        return [
            .init(
                point: first,
                text: "\(fmt(first.value))\(suffix)",
                color: Color.white.opacity(0.82),
                xOffset: 7
            )
        ]
    }

    func render(_ lens: TodayLens) -> RenderedLens {
        switch lens {
        case .progress: progressLens()
        case .currentWeight: currentWeightLens()
        case .totalLost: totalLostLens()
        case .thisWeek: thisWeekLens()
        case .weeklyAverage: weeklyAverageLens()
        case .recentTrend: recentTrendLens()
        case .pace: paceHistoryLens()
        case .forecast: forecastLens()
        case .fullCut: fullCutLens()
        case .weeklyRange: weeklyRangeLens()
        case .weeklyLoss: weekOverWeekLens()
        }
    }

    // MARK: - Progress vs Plan

    private func progressLens() -> RenderedLens {
        let trend = analytics.currentTrend
        let heroValue = trend.map { num($0.value) } ?? dash
        let context: String? = trend.map {
            "7-day trend · \(dateStr($0.date))"
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
        spec.pointLabels = firstValueLabel(dp(analytics.observations))
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

    // MARK: - Current Weight

    private func currentWeightLens() -> RenderedLens {
        let latest = analytics.latestObservation
        let heroValue = latest.map { num($0.value) } ?? dash
        let context = latest.map { "Latest · \(dateStr($0.date))" }
        let end = latest?.date ?? analytics.asOfDate
        let requestedStart = calendar.date(byAdding: .day, value: -29, to: end) ?? end
        let observations = analytics.observations.filter { $0.date >= requestedStart && $0.date <= end }
        let trend = analytics.trend.filter { $0.date >= requestedStart && $0.date <= end }
        let start = observations.first?.date ?? requestedStart
        let xDomain = start...max(start, end)
        let domainLb = recentWeightDomain(observations.map(\.value) + trend.map(\.value))
        let observationsD = dp(observations)
        let trendD = dp(trend)

        var spec = LensPlotSpec(
            xDomain: xDomain,
            yDomain: disp(domainLb.lowerBound)...disp(domainLb.upperBound)
        )
        spec.references = weightAxisReferences(domainLb)
        if observationsD.count >= 2 {
            spec.series.append(.init(points: observationsD, color: secondaryLine, lineWidth: 1.2, smooth: false))
        }
        spec.series.append(.init(points: trendD, color: lineColor, lineWidth: 2.8, smooth: false, haloColor: lineHalo))
        spec.markerSets = [.init(points: observationsD, color: markerColor, radius: 2.6)]
        spec.pointLabels = firstValueLabel(observationsD)
        spec.maskBoundary = trendD
        if let last = observationsD.last {
            spec.endpoint = .init(point: last, color: .white, radius: 5, haloColor: TodayLens.currentWeight.accent)
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let windowChange = observations.first.flatMap { first in latest.map { $0.value - first.value } }
        let stats = [
            LensStat(label: "7-day trend", value: analytics.currentTrend.map { "\(num($0.value)) \(sym)" } ?? dash),
            LensStat(label: "30-day change", value: windowChange.map { "\(rate($0)) \(sym)" } ?? dash),
            LensStat(label: "Plan today", value: "\(num(analytics.plannedWeightAsOfLb)) \(sym)"),
        ]
        let scrub = scrubModel(
            points: observationsD,
            heroUnit: sym,
            value: { _, point in fmt(point.value) },
            context: { _, point in "Observed · \(dateStr(point.date))" },
            secondary: { _, _ in analytics.currentTrend.map { "trend \(num($0.value)) \(sym)" } }
        )
        return RenderedLens(
            lens: .currentWeight,
            heroValue: heroValue,
            heroUnit: sym,
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: "Current weight \(heroValue) \(sym). Seven-day trend \(stats[0].value).",
            scrub: scrub
        )
    }

    // MARK: - Total Lost

    private func totalLostLens() -> RenderedLens {
        let cumulative = analytics.observations.map {
            DatedValue(date: $0.date, value: analytics.startWeightLb - $0.value)
        }
        let cumulativeD = dp(cumulative)
        let latest = cumulative.last
        let goalLoss = analytics.startWeightLb - analytics.targetWeightLb
        let heroValue = latest.map { num($0.value) } ?? dash
        let context = "Since \(dateStr(analytics.startDate))"
        let xDomain = analytics.startDate...max(analytics.startDate, analytics.asOfDate)
        let values = cumulative.map(\.value) + [0, goalLoss]
        let domainLb = stableWeightDomain(values)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: disp(domainLb.lowerBound)...disp(domainLb.upperBound))
        spec.references = weightAxisReferences(domainLb)
        spec.references.append(
            .init(kind: .horizontal(disp(goalLoss)), color: Color.white.opacity(0.42), dash: [3, 4], label: "Goal \(num(goalLoss))", labelColor: labelColor)
        )
        spec.series = [.init(points: cumulativeD, color: lineColor, lineWidth: 2.8, smooth: false, haloColor: lineHalo)]
        spec.markerSets = [.init(points: cumulativeD, color: markerColor, radius: 2.2)]
        spec.pointLabels = firstValueLabel(cumulativeD)
        spec.maskBoundary = cumulativeD
        if let last = cumulativeD.last {
            spec.endpoint = .init(point: last, color: .white, radius: 5, haloColor: TodayLens.totalLost.accent)
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let stats = [
            LensStat(label: "Start", value: "\(num(analytics.startWeightLb)) \(sym)"),
            LensStat(label: "Current trend", value: analytics.currentTrend.map { "\(num($0.value)) \(sym)" } ?? dash),
            LensStat(label: "Goal loss", value: "\(num(goalLoss)) \(sym)"),
        ]
        let scrub = scrubModel(
            points: cumulativeD,
            heroUnit: "\(sym) lost",
            value: { _, point in fmt(point.value) },
            context: { _, point in dateStr(point.date) },
            secondary: { _, point in goalLoss > 0 ? "\(Int((point.value / disp(goalLoss) * 100).rounded()))% of goal" : nil }
        )
        return RenderedLens(
            lens: .totalLost,
            heroValue: heroValue,
            heroUnit: "\(sym) lost",
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: "Total lost \(heroValue) \(sym) since \(dateStr(analytics.startDate)).",
            scrub: scrub
        )
    }

    // MARK: - This Week

    private func thisWeekLens() -> RenderedLens {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        mondayCalendar.minimumDaysInFirstWeek = 4
        let today = mondayCalendar.startOfDay(for: analytics.asOfDate)
        let weekStart = mondayCalendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let fullEnd = mondayCalendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let weekEnd = min(today, fullEnd)
        let inWeek = analytics.observations.filter { $0.date >= weekStart && $0.date <= weekEnd }
        let prior = analytics.observations.last { $0.date < weekStart }
        let baseline = prior?.value ?? inWeek.first?.value
        let points = baseline.map { base in
            inWeek.map { DatedValue(date: $0.date, value: $0.value - base) }
        } ?? []
        let pointsD = dp(points)
        let heroValue = points.last.map { rate($0.value) } ?? dash
        let context = "WTD · \(dateStr(weekStart))–\(dateStr(weekEnd))"
        let magnitude = max(2, ceil(points.map { abs($0.value) }.max() ?? 0))
        let domainLb = (-magnitude)...magnitude

        var spec = LensPlotSpec(xDomain: weekStart...max(weekStart, fullEnd), yDomain: disp(domainLb.lowerBound)...disp(domainLb.upperBound))
        spec.references = weightAxisReferences(domainLb)
        spec.references.append(.init(kind: .horizontal(0), color: Color.white.opacity(0.42), dash: [3, 4], label: "Mon", labelColor: labelColor))
        if pointsD.count >= 2 {
            spec.series = [.init(points: pointsD, color: lineColor, lineWidth: 2.8, smooth: false, haloColor: lineHalo)]
            spec.maskBoundary = pointsD
        }
        spec.markerSets = [.init(points: pointsD, color: markerColor, radius: 2.8)]
        spec.pointLabels = firstValueLabel(pointsD)
        if let last = pointsD.last {
            spec.endpoint = .init(point: last, color: .white, radius: 5, haloColor: TodayLens.thisWeek.accent)
        }
        spec.dateLabels = [
            .init(date: weekStart, text: dateStr(weekStart), color: labelColor),
            .init(date: fullEnd, text: dateStr(fullEnd), color: labelColor),
        ]

        let average = inWeek.isEmpty ? nil : inWeek.map(\.value).reduce(0, +) / Double(inWeek.count)
        let stats = [
            LensStat(label: "Baseline", value: baseline.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "WTD average", value: average.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "Logged", value: "\(inWeek.count)d"),
        ]
        let scrub = scrubModel(
            points: pointsD,
            heroUnit: sym,
            value: { _, point in fmt(point.value) },
            context: { _, point in dateStr(point.date) },
            secondary: { _, point in baseline.map { "weight \(fmt(disp($0) + point.value)) \(sym)" } }
        )
        return RenderedLens(
            lens: .thisWeek,
            heroValue: heroValue,
            heroUnit: sym,
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: "This week changed \(heroValue) \(sym) through \(dateStr(weekEnd)).",
            scrub: scrub
        )
    }

    // MARK: - Recent Trend

    private func recentTrendLens() -> RenderedLens {
        let fit = analytics.recentPace
        let heroValue = fit.map { rate($0.signedLbPerWeek) } ?? dash
        let context: String? = fit.map {
            "14-day fit · \(dateStr($0.windowStart))–\(dateStr($0.windowEnd))"
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
        spec.pointLabels = firstValueLabel(dp(trend))
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

    // MARK: - Week-to-Date Average

    private func weeklyAverageLens() -> RenderedLens {
        let visible = Array(weekly.points.suffix(9))
        let current = visible.last
        let heroValue = current.map { num($0.averageWeight) } ?? dash
        let context = current.map {
            "\($0.isWeekToDate ? "WTD" : ($0.isPartial ? "Partial" : "Week")) · \(dateStr($0.weekStart))–\(dateStr($0.weekEnd))"
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
        spec.pointLabels = firstValueLabel(dp(averages))
        spec.maskBoundary = dp(averages)
        spec.maskBoundarySmooth = false
        if let last = averages.last {
            spec.endpoint = .init(
                point: DatedValue(date: last.date, value: disp(last.value)),
                color: .white,
                radius: 5,
                haloColor: TodayLens.weeklyAverage.accent
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
        let a11y = "Week-to-date average. \(heroValue) \(sym). Observed range \(range) \(sym)."
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
                return "observed \(num(point.minWeight))–\(num(point.maxWeight)) \(sym)"
            }
        )
        return RenderedLens(
            lens: .weeklyAverage,
            heroValue: heroValue,
            heroUnit: sym,
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: a11y,
            scrub: scrub
        )
    }

    // MARK: - Pace History

    private func paceHistoryLens() -> RenderedLens {
        var history: [DatedValue] = []
        for index in analytics.observations.indices {
            let prefix = Array(analytics.observations[...index])
            if let fit = TodayAnalyticsModel.recentPaceFit(observations: prefix, calendar: calendar) {
                history.append(DatedValue(date: fit.windowEnd, value: fit.signedLbPerWeek))
            }
        }
        let end = history.last?.date ?? analytics.asOfDate
        let requestedStart = calendar.date(byAdding: .day, value: -55, to: end) ?? end
        let visible = history.filter { $0.date >= requestedStart }
        let visibleD = dp(visible)
        let start = visible.first?.date ?? requestedStart
        let neededSigned: Double? = {
            guard case .available(let magnitude) = analytics.neededNow else { return nil }
            return -magnitude
        }()
        let required = neededSigned ?? -analytics.originalPlannedLossLbPerWeek
        let values = visible.map(\.value) + [required, 0]
        let magnitude = max(2, ceil(values.map { abs($0) }.max() ?? 2))
        let domainLb = (-magnitude)...magnitude
        let heroValue = analytics.recentPace.map { rate($0.signedLbPerWeek) } ?? dash
        let context = "14-day rolling fit"

        var spec = LensPlotSpec(xDomain: start...max(start, end), yDomain: disp(domainLb.lowerBound)...disp(domainLb.upperBound))
        spec.references = weightAxisReferences(domainLb)
        spec.references.append(
            .init(kind: .horizontal(disp(required)), color: Color.white.opacity(0.42), dash: [4, 3], label: "Needed", labelColor: labelColor)
        )
        if visibleD.count >= 2 {
            spec.series = [.init(points: visibleD, color: lineColor, lineWidth: 2.6, smooth: false, haloColor: lineHalo)]
            spec.maskBoundary = visibleD
        }
        spec.markerSets = [.init(points: visibleD, color: markerColor, radius: 2.2)]
        spec.pointLabels = firstValueLabel(visibleD)
        if let last = visibleD.last {
            spec.endpoint = .init(point: last, color: .white, radius: 5, haloColor: TodayLens.pace.accent)
        }
        spec.dateLabels = evenlySpacedDateLabels(start...max(start, end))

        let neededText: String = {
            switch analytics.neededNow {
            case .available(let value): return "\(lossRate(value)) \(sym)/wk"
            case .goalReached: return "Goal reached"
            case .deadlinePassed: return "Deadline passed"
            case .insufficientData: return dash
            }
        }()
        let stats = [
            LensStat(label: "Recent", value: analytics.recentPace.map { "\(rate($0.signedLbPerWeek)) \(sym)/wk" } ?? dash),
            LensStat(label: "Needed now", value: neededText),
            LensStat(label: "Original plan", value: "\(lossRate(analytics.originalPlannedLossLbPerWeek)) \(sym)/wk"),
        ]
        let scrub = scrubModel(
            points: visibleD,
            heroUnit: "\(sym)/week",
            value: { _, point in fmt(point.value) },
            context: { _, point in "Fit · \(dateStr(point.date))" },
            secondary: { _, point in "needed \(fmt(disp(required))) \(sym)/wk · gap \(fmt(point.value - disp(required)))" }
        )
        return RenderedLens(
            lens: .pace,
            heroValue: heroValue,
            heroUnit: "\(sym)/week",
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: "Historical fourteen-day pace. Recent pace \(stats[0].value).",
            scrub: scrub
        )
    }

    // MARK: - Forecast

    private func forecastLens() -> RenderedLens {
        let forecast = analytics.forecast
        let heroValue = forecast.map { num($0.projectedTargetWeightLb) } ?? dash
        let context = "For \(dateStr(analytics.targetDate))"
        let currentDate = analytics.currentTrend?.date ?? analytics.asOfDate
        let historyStart = calendar.date(byAdding: .day, value: -29, to: currentDate) ?? currentDate
        let history = analytics.trend.filter { $0.date >= historyStart && $0.date <= currentDate }
        let historyD = dp(history)
        let start = history.first?.date ?? historyStart
        let xDomain = start...max(start, analytics.targetDate)
        var values = history.map(\.value) + [analytics.targetWeightLb]
        if let forecast { values += [forecast.lowerTargetWeightLb, forecast.upperTargetWeightLb] }
        let domainLb = stableWeightDomain(values)

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: disp(domainLb.lowerBound)...disp(domainLb.upperBound))
        spec.references = weightAxisReferences(domainLb)
        spec.references.append(
            .init(kind: .horizontal(disp(analytics.targetWeightLb)), color: Color.white.opacity(0.42), dash: [3, 4], label: "Target", labelColor: labelColor)
        )
        spec.series = [.init(points: historyD, color: lineColor, lineWidth: 2.8, smooth: false, haloColor: lineHalo)]
        if let forecast {
            spec.bands = [.init(lower: dp(forecast.lowerLine), upper: dp(forecast.upperLine), color: .white, opacity: 0.13, smooth: false)]
            spec.series.append(.init(points: dp(forecast.centerLine), color: Color.white.opacity(0.82), lineWidth: 2, dash: [5, 4], smooth: false))
        }
        let boundary = historyD + (forecast.map { dp($0.centerLine.filter { $0.date > currentDate }) } ?? [])
        spec.maskBoundary = boundary
        spec.pointLabels = firstValueLabel(historyD)
        if let current = analytics.currentTrend {
            spec.endpoint = .init(
                point: DatedValue(date: currentDate, value: disp(current.value)),
                color: .white,
                radius: 5,
                haloColor: TodayLens.forecast.accent
            )
        }
        spec.dateLabels = [
            .init(date: start, text: dateStr(start), color: labelColor),
            .init(date: currentDate, text: dateStr(currentDate), color: labelColor),
            .init(date: analytics.targetDate, text: dateStr(analytics.targetDate), color: labelColor),
        ]

        let range = forecast.map { "\(num($0.lowerTargetWeightLb))–\(num($0.upperTargetWeightLb))" } ?? dash
        let stats = [
            LensStat(label: "Target", value: "\(num(analytics.targetWeightLb)) \(sym)"),
            LensStat(label: "Fit range", value: range),
            LensStat(label: "Anchor", value: analytics.currentTrend.map { "\(num($0.value)) \(sym)" } ?? dash),
        ]
        let scrubPoints = boundary
        let scrub = scrubModel(
            points: scrubPoints,
            heroUnit: sym,
            value: { _, point in fmt(point.value) },
            context: { _, point in "\(dateStr(point.date))\(point.date > currentDate ? " · forecast" : " · trend")" },
            secondary: { _, point in "\(fmt(point.value - disp(analytics.targetWeightLb))) \(sym) vs target" }
        )
        return RenderedLens(
            lens: .forecast,
            heroValue: heroValue,
            heroUnit: sym,
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: forecast == nil ? "Forecast unavailable." : "Projected \(heroValue) \(sym) for \(dateStr(analytics.targetDate)).",
            scrub: scrub
        )
    }

    // MARK: - Full Cut

    private func fullCutLens() -> RenderedLens {
        let observationsD = dp(analytics.observations)
        let trendD = dp(analytics.trend)
        let heroValue = analytics.currentTrend.map { num($0.value) } ?? dash
        let context = "\(dateStr(analytics.startDate))–\(dateStr(analytics.targetDate))"
        let xDomain = analytics.startDate...max(analytics.startDate, analytics.targetDate)
        let domainLb = stableWeightDomain(
            analytics.observations.map(\.value) + analytics.trend.map(\.value) + [analytics.startWeightLb, analytics.targetWeightLb]
        )

        var spec = LensPlotSpec(xDomain: xDomain, yDomain: disp(domainLb.lowerBound)...disp(domainLb.upperBound))
        spec.references = weightAxisReferences(domainLb)
        spec.references.append(
            .init(kind: .horizontal(disp(analytics.targetWeightLb)), color: Color.white.opacity(0.42), dash: [3, 4], label: "Target", labelColor: labelColor)
        )
        if observationsD.count >= 2 {
            spec.series.append(.init(points: observationsD, color: secondaryLine, lineWidth: 1.2, smooth: false))
        }
        spec.series.append(.init(points: trendD, color: lineColor, lineWidth: 2.8, smooth: false, haloColor: lineHalo))
        spec.markerSets = [.init(points: observationsD, color: markerColor, radius: 2)]
        spec.pointLabels = firstValueLabel(observationsD)
        spec.maskBoundary = trendD
        if let current = analytics.currentTrend {
            spec.endpoint = .init(
                point: DatedValue(date: current.date, value: disp(current.value)),
                color: .white,
                radius: 5,
                haloColor: TodayLens.fullCut.accent
            )
        }
        spec.dateLabels = evenlySpacedDateLabels(xDomain)

        let lost = analytics.currentTrend.map { analytics.startWeightLb - $0.value }
        let stats = [
            LensStat(label: "Start", value: "\(num(analytics.startWeightLb)) \(sym)"),
            LensStat(label: "Trend loss", value: lost.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "Target", value: "\(num(analytics.targetWeightLb)) \(sym)"),
        ]
        let scrub = scrubModel(
            points: observationsD,
            heroUnit: sym,
            value: { _, point in fmt(point.value) },
            context: { _, point in dateStr(point.date) },
            secondary: { _, point in "\(fmt(point.value - disp(analytics.targetWeightLb))) \(sym) vs target" }
        )
        return RenderedLens(
            lens: .fullCut,
            heroValue: heroValue,
            heroUnit: sym,
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: "Full cut from \(dateStr(analytics.startDate)) to \(dateStr(analytics.targetDate)). Current trend \(heroValue) \(sym).",
            scrub: scrub
        )
    }

    // MARK: - Weekly Range

    private func weeklyRangeLens() -> RenderedLens {
        let visible = Array(weekly.points.suffix(9))
        let current = visible.last
        let averages = visible.map { DatedValue(date: $0.weekStart, value: $0.averageWeight) }
        let averagesD = dp(averages)
        let extremes = visible.flatMap { [$0.minWeight, $0.maxWeight] }
        let domainLb = recentWeightDomain(extremes)
        let start = visible.first?.weekStart ?? analytics.startDate
        let end = visible.last?.weekStart ?? start
        let currentSpan = current.map { $0.maxWeight - $0.minWeight }
        let heroValue = currentSpan.map { num($0) } ?? dash
        let context = current.map { "Observed span · \(dateStr($0.weekStart))" }

        var spec = LensPlotSpec(xDomain: start...max(start, end), yDomain: disp(domainLb.lowerBound)...disp(domainLb.upperBound))
        spec.references = weightAxisReferences(domainLb)
        spec.whiskers = visible.map {
            .init(date: $0.weekStart, low: disp($0.minWeight), high: disp($0.maxWeight), color: Color.white.opacity(0.55), lineWidth: 1.6, capWidth: 9)
        }
        spec.series = [.init(points: averagesD, color: lineColor, lineWidth: 2.6, smooth: false, haloColor: lineHalo)]
        spec.markerSets = [.init(points: averagesD, color: markerColor, radius: 2.6)]
        spec.pointLabels = firstValueLabel(averagesD)
        spec.maskBoundary = averagesD
        if let last = averagesD.last {
            spec.endpoint = .init(point: last, color: .white, radius: 5, haloColor: TodayLens.weeklyRange.accent)
        }
        spec.dateLabels = evenlySpacedDateLabels(start...max(start, end))

        let stats = [
            LensStat(label: "Average", value: current.map { "\(num($0.averageWeight)) \(sym)" } ?? dash),
            LensStat(label: "Observed low", value: current.map { "\(num($0.minWeight)) \(sym)" } ?? dash),
            LensStat(label: "Observed high", value: current.map { "\(num($0.maxWeight)) \(sym)" } ?? dash),
        ]
        let scrub = scrubModel(
            points: averagesD,
            heroUnit: sym,
            value: { _, point in fmt(point.value) },
            context: { index, point in "\(dateStr(point.date))\(visible[index].isWeekToDate ? " · WTD" : "")" },
            secondary: { index, _ in "range \(num(visible[index].minWeight))–\(num(visible[index].maxWeight)) \(sym)" }
        )
        return RenderedLens(
            lens: .weeklyRange,
            heroValue: heroValue,
            heroUnit: "\(sym) range",
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: "Current observed weekly range \(heroValue) \(sym).",
            scrub: scrub
        )
    }

    // MARK: - Week-over-Week Change

    private func weekOverWeekLens() -> RenderedLens {
        let comparable = Array(weekly.points.filter { $0.lossVsPrevious != nil }.suffix(9))
        // Conventional signed change in the weekly mean: negative means the
        // average fell. This matches both the bars and all other weight slopes.
        let changes = comparable.map {
            DatedValue(date: $0.weekStart, value: -($0.lossVsPrevious ?? 0))
        }
        let changesD = dp(changes)
        let latest = changes.last
        let required = -weekly.requiredWeeklyLoss
        let values = changes.map(\.value) + [required, 0]
        let magnitude = max(1, ceil((values.map { abs($0) }.max() ?? 1) * 2) / 2)
        let domainLb = (-magnitude)...magnitude
        let firstDate = changes.first?.date ?? analytics.asOfDate
        let lastDate = changes.last?.date ?? firstDate
        let xLower = calendar.date(byAdding: .day, value: -3, to: firstDate) ?? firstDate
        let xUpper = calendar.date(byAdding: .day, value: 3, to: lastDate) ?? lastDate
        let heroValue = latest.map { rate($0.value) } ?? dash
        let latestPoint = comparable.last
        let context = latestPoint.map {
            "\($0.isWeekToDate ? "WTD vs matched" : "Vs prior week") · \(dateStr($0.weekStart))"
        } ?? "No comparison yet"

        var spec = LensPlotSpec(xDomain: xLower...max(xLower, xUpper), yDomain: disp(domainLb.lowerBound)...disp(domainLb.upperBound))
        spec.references = weightAxisReferences(domainLb)
        spec.references.append(
            .init(kind: .horizontal(disp(required)), color: Color.white.opacity(0.48), dash: [4, 3], label: "Plan", labelColor: labelColor)
        )
        spec.bars = [.init(points: changesD, baseline: 0, color: .white, width: 18, opacity: 0.82)]
        spec.pointLabels = firstValueLabel(changesD)
        spec.dateLabels = evenlySpacedDateLabels(xLower...max(xLower, xUpper))

        let currentAverage = latestPoint?.averageWeight
        let previousAverage = latestPoint.flatMap { point -> Double? in
            guard let loss = point.lossVsPrevious else { return nil }
            return point.averageWeight + loss
        }
        let stats = [
            LensStat(label: latestPoint?.isWeekToDate == true ? "Prior matched" : "Previous", value: previousAverage.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "Current mean", value: currentAverage.map { "\(num($0)) \(sym)" } ?? dash),
            LensStat(label: "Planned change", value: "\(rate(required)) \(sym)"),
        ]
        let scrub = scrubModel(
            points: changesD,
            heroUnit: sym,
            value: { _, point in fmt(point.value) },
            context: { index, point in "\(dateStr(point.date))\(comparable[index].isWeekToDate ? " · WTD" : "")" },
            secondary: { _, point in "plan \(fmt(disp(required))) \(sym) · gap \(fmt(point.value - disp(required)))" }
        )
        return RenderedLens(
            lens: .weeklyLoss,
            heroValue: heroValue,
            heroUnit: sym,
            heroContext: context,
            stats: stats,
            plot: spec,
            accessibilitySummary: "Week-over-week mean change \(heroValue) \(sym).",
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
