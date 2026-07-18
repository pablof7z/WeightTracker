import SwiftUI
import Charts

struct StableCutChart: View {
    let model: TransformedCutChartModel
    let unit: WeightUnit
    var showXAxis: Bool = false

    private struct BandPoint: Identifiable {
        let date: Date
        let low: Double
        let high: Double
        var id: Date { date }
    }

    private var isPercent: Bool { model.variation == .completionPercent }
    private var isRecent: Bool { model.variation == .recentFocus }
    private var isPace: Bool { model.variation == .paceDelta }

    private func display(_ value: Double) -> Double {
        guard !isPercent else { return value }
        return unit == .lbs ? value : UnitConvert.lbToKg(value)
    }

    private func displayed(_ points: [DatedValue]) -> [DatedValue] {
        points.map { DatedValue(date: $0.date, value: display($0.value)) }
    }

    private var raw: [DatedValue] { displayed(model.raw) }
    private var trend: [DatedValue] { displayed(model.trend) }
    private var required: [DatedValue] { displayed(model.required) }
    private var best: [DatedValue] { displayed(model.bestForecast) }
    private var typical: [DatedValue] { displayed(model.typicalForecast) }
    private var worst: [DatedValue] { displayed(model.worstForecast) }
    private var anchor: DatedValue {
        DatedValue(date: model.forecastAnchor.date, value: display(model.forecastAnchor.value))
    }
    private var yDomain: ClosedRange<Double> {
        display(model.yDomain.lowerBound)...display(model.yDomain.upperBound)
    }

    private var band: [BandPoint] {
        let bestByDate = Dictionary(uniqueKeysWithValues: best.map { ($0.date, $0.value) })
        return worst.compactMap { point in
            guard let other = bestByDate[point.date] else { return nil }
            return BandPoint(date: point.date, low: min(point.value, other), high: max(point.value, other))
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        Chart {
            ForEach(band) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Best", point.low),
                    yEnd: .value("Worst", point.high)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(Color.accentColor.opacity(isRecent ? 0.07 : 0.10))
            }

            if isPace {
                RectangleMark(
                    xStart: .value("Start", model.xDomain.lowerBound),
                    xEnd: .value("End", model.xDomain.upperBound),
                    yStart: .value("On pace", 0),
                    yEnd: .value("Ahead", yDomain.upperBound)
                )
                .foregroundStyle(Color.green.opacity(0.035))

                RectangleMark(
                    xStart: .value("Start", model.xDomain.lowerBound),
                    xEnd: .value("End", model.xDomain.upperBound),
                    yStart: .value("Behind", yDomain.lowerBound),
                    yEnd: .value("On pace", 0)
                )
                .foregroundStyle(Color.red.opacity(0.03))
            }

            if !isRecent && !isPace {
                ForEach(required) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Required pace", point.value),
                        series: .value("Series", "required")
                    )
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [1.5, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.65))
                }
            }

            if !isRecent {
                ForEach(best) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Best forecast", point.value),
                        series: .value("Series", "best")
                    )
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .foregroundStyle(Color.green.opacity(0.7))
                }
            }

            ForEach(typical) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Typical forecast", point.value),
                    series: .value("Series", "typical")
                )
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: isRecent ? 1.8 : 1.5, dash: [6, 4]))
                .foregroundStyle(Color.accentColor.opacity(0.9))
            }

            if !isRecent {
                ForEach(worst) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Worst forecast", point.value),
                        series: .value("Series", "worst")
                    )
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .foregroundStyle(Color.red.opacity(0.65))
                }
            }

            ForEach(raw) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Raw weight", point.value)
                )
                .symbolSize(isRecent ? 18 : 12)
                .foregroundStyle(Color.primary.opacity(0.28))
            }

            ForEach(trend) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Trailing 7-day trend", point.value),
                    series: .value("Series", "trend")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .foregroundStyle(Color.primary)
            }

            PointMark(
                x: .value("Forecast anchor date", anchor.date),
                y: .value("Forecast anchor", anchor.value)
            )
            .symbolSize(90)
            .symbol(.circle)
            .foregroundStyle(Color(.systemBackground))

            PointMark(
                x: .value("Forecast anchor date", anchor.date),
                y: .value("Forecast anchor", anchor.value)
            )
            .symbolSize(90)
            .symbol(.circle.strokeBorder(lineWidth: 2.2))
            .foregroundStyle(Color.accentColor)

            if isRecent {
                RuleMark(x: .value("Forecast begins", anchor.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .annotation(position: .top, alignment: .trailing, spacing: 4) {
                        Text("Forecast begins")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }

            if let baseline = model.baseline {
                RuleMark(y: .value("Baseline", display(baseline)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .annotation(position: .trailing, alignment: .leading, spacing: 3) {
                        Text(isPace ? "On pace" : "Start")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }

            if let target = model.targetLine, model.yDomain.contains(target) {
                RuleMark(y: .value("Target", display(target)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .annotation(position: .trailing, alignment: .leading, spacing: 3) {
                        Text(model.variation == .remainingToGoal ? "Goal" : "Target")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: model.xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            if showXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.10))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisLabel(number))
                            .font(.system(size: 9).monospacedDigit())
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.variation.label) chart")
    }

    private func axisLabel(_ value: Double) -> String {
        if isPercent { return String(format: "%.0f%%", value) }
        return String(format: abs(value) < 10 ? "%.1f" : "%.0f", value)
    }
}

extension TransformedCutChartModel {
    var latestTrendValue: Double? { trend.last?.value }
}
