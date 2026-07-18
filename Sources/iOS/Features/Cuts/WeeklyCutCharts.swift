import SwiftUI
import Charts

/// The four weekly aggregation chart modes for the active cut. All four
/// consume the same `[WeeklyCutPoint]` output from `WeeklyCutAggregator` —
/// no view recomputes weekly statistics itself.
enum WeeklyCutChartMode: String, CaseIterable, Identifiable, Sendable {
    case weeklyAverage
    case weeklyVolatility
    case weeklyLoss
    case weeklyPace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weeklyAverage: return "Weekly average"
        case .weeklyVolatility: return "Weekly average + volatility"
        case .weeklyLoss: return "Exact weekly loss"
        case .weeklyPace: return "Weekly average vs required pace"
        }
    }

    var detail: String {
        switch self {
        case .weeklyAverage: return "One point per week with average weight and reading count"
        case .weeklyVolatility: return "Weekly average with a min–max range for each week"
        case .weeklyLoss: return "Exact pounds lost or gained week over week"
        case .weeklyPace: return "Actual weekly average against the required pace"
        }
    }
}

/// Weight-unit-aware formatting shared by every weekly chart mode.
private func displayWeight(_ lb: Double, unit: WeightUnit) -> Double {
    unit == .lbs ? lb : UnitConvert.lbToKg(lb)
}

/// `lossVsPrevious` is `previous - current`, so a positive value means the
/// average weight decreased. Render that as a loss (green, minus sign).
private func formattedLoss(_ lossLb: Double, unit: WeightUnit) -> (text: String, isGood: Bool) {
    let displayValue = displayWeight(lossLb, unit: unit)
    let text = String(format: "%@%.1f %@", displayValue >= 0 ? "−" : "+", abs(displayValue), unit.symbol)
    return (text, displayValue >= 0)
}

struct WeeklyCutChartView: View {
    let points: [WeeklyCutPoint]
    let mode: WeeklyCutChartMode
    let unit: WeightUnit
    let requiredWeeklyRateLb: Double

    var body: some View {
        if points.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Not enough data for a weekly view yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            switch mode {
            case .weeklyAverage:
                WeeklyAverageChart(points: points, unit: unit)
            case .weeklyVolatility:
                WeeklyVolatilityChart(points: points, unit: unit)
            case .weeklyLoss:
                WeeklyLossChart(points: points, unit: unit, requiredWeeklyRateLb: requiredWeeklyRateLb)
            case .weeklyPace:
                WeeklyPaceChart(points: points, unit: unit)
            }
        }
    }
}

/// 1. Weekly average: one line, one point per week, labeled with the average
/// weight and reading count, and the exact weekly loss per segment.
private struct WeeklyAverageChart: View {
    let points: [WeeklyCutPoint]
    let unit: WeightUnit

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Average", displayWeight(point.averageWeight, unit: unit))
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(WTColor.avgLine)

                PointMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Average", displayWeight(point.averageWeight, unit: unit))
                )
                .symbol(point.isPartial ? .square : .circle)
                .symbolSize(point.isPartial ? 42 : 70)
                .foregroundStyle(point.isWeekToDate ? Color.orange : WTColor.avgLine)
                .annotation(position: .top) {
                    weekAnnotation(point)
                }
            }
        }
        .weeklyChartStyle(unit: unit)
    }

    @ViewBuilder
    private func weekAnnotation(_ point: WeeklyCutPoint) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%.1f %@", displayWeight(point.averageWeight, unit: unit), unit.symbol))
                .font(.system(size: 9, weight: .semibold))
            Text("n=\(point.readingCount)")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            if let loss = point.lossVsPrevious {
                let formatted = formattedLoss(loss, unit: unit)
                Text(formatted.text)
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(formatted.isGood ? .green : .red)
            }
            if point.isWeekToDate {
                Text("WTD")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.orange)
            } else if point.isPartial {
                Text("Partial")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 2. Weekly average + volatility: same average line plus min–max whiskers.
private struct WeeklyVolatilityChart: View {
    let points: [WeeklyCutPoint]
    let unit: WeightUnit

    var body: some View {
        Chart {
            ForEach(points) { point in
                RuleMark(
                    x: .value("Week", point.weekStart),
                    yStart: .value("Min", displayWeight(point.minWeight, unit: unit)),
                    yEnd: .value("Max", displayWeight(point.maxWeight, unit: unit))
                )
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .foregroundStyle(Color.secondary.opacity(0.45))

                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Average", displayWeight(point.averageWeight, unit: unit))
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(WTColor.avgLine)

                PointMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Average", displayWeight(point.averageWeight, unit: unit))
                )
                .symbol(point.isPartial ? .square : .circle)
                .symbolSize(point.isPartial ? 42 : 70)
                .foregroundStyle(point.isWeekToDate ? Color.orange : WTColor.avgLine)
                .annotation(position: .top) {
                    if let loss = point.lossVsPrevious {
                        let formatted = formattedLoss(loss, unit: unit)
                        Text(formatted.text)
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(formatted.isGood ? .green : .red)
                    } else if point.isWeekToDate {
                        Text("WTD")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .weeklyChartStyle(unit: unit)
    }
}

/// 3. Exact weekly loss: bar chart of `lossVsPrevious` with a horizontal
/// required-rate line. Positive bars mean average weight decreased.
private struct WeeklyLossChart: View {
    let points: [WeeklyCutPoint]
    let unit: WeightUnit
    let requiredWeeklyRateLb: Double

    private var lossPoints: [WeeklyCutPoint] {
        points.filter { $0.lossVsPrevious != nil }
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Required rate", displayWeight(requiredWeeklyRateLb, unit: unit)))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                .foregroundStyle(Color.secondary.opacity(0.65))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Required rate")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }

            ForEach(lossPoints) { point in
                let loss = displayWeight(point.lossVsPrevious ?? 0, unit: unit)
                BarMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Loss", loss),
                    width: .fixed(18)
                )
                .foregroundStyle(loss >= 0 ? Color.green : Color.red)
                .annotation(position: loss >= 0 ? .top : .bottom) {
                    VStack(spacing: 1) {
                        Text(String(format: "%+.1f", loss))
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(loss >= 0 ? .green : .red)
                        if point.isWeekToDate {
                            Text("WTD")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.1f %@", v, unit.symbol))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 160)
    }
}

/// 4. Weekly average vs required pace: actual and planned lines with the
/// gap shaded and each week labeled with pounds ahead or behind.
private struct WeeklyPaceChart: View {
    let points: [WeeklyCutPoint]
    let unit: WeightUnit

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Week", point.weekStart),
                    yStart: .value("Average", displayWeight(point.averageWeight, unit: unit)),
                    yEnd: .value("Planned", displayWeight(point.plannedAverage, unit: unit))
                )
                .foregroundStyle(Color.accentColor.opacity(0.12))
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Average", displayWeight(point.averageWeight, unit: unit)),
                    series: .value("Series", "actual")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(WTColor.avgLine)

                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Planned", displayWeight(point.plannedAverage, unit: unit)),
                    series: .value("Series", "planned")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(Color.secondary)

                PointMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Average", displayWeight(point.averageWeight, unit: unit))
                )
                .symbol(point.isPartial ? .square : .circle)
                .symbolSize(point.isPartial ? 42 : 60)
                .foregroundStyle(point.isWeekToDate ? Color.orange : WTColor.avgLine)
                .annotation(position: .top) {
                    let displayed = displayWeight(point.aheadOfPlan, unit: unit)
                    Text(String(format: "%+.1f %@", displayed, unit.symbol))
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(point.aheadOfPlan >= 0 ? .green : .red)
                }
            }
        }
        .weeklyChartStyle(unit: unit)
    }
}

private extension View {
    /// Shared axis presentation for the line-based weekly charts.
    func weeklyChartStyle(unit: WeightUnit) -> some View {
        self
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v.rounded())) \(unit.symbol)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 170)
    }
}
