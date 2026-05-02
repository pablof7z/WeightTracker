import SwiftUI
import Charts

struct CutProjectionChartContent: View {
    let active: ActiveCut
    let inCutReadings: [Reading]
    let projection: CutProjectionResult
    let unit: WeightUnit
    var height: CGFloat = 96
    var hideXAxisLabels: Bool = false

    static let avgColor: Color = .blue
    static let bestColor: Color = .green
    static let worstColor: Color = Color(red: 0.78, green: 0.30, blue: 0.30)

    private func display(_ kg: Double) -> Double {
        UnitConvert.displayWeight(kg: kg, in: unit)
    }

    private var allWeightsKg: [Double] {
        var w = inCutReadings.map(\.weightKg)
        w.append(active.startWeightKg)
        w.append(active.targetWeightKg)
        w.append(projection.anchorKg)
        if let b = projection.bestEndKg { w.append(b) }
        if let wr = projection.worstEndKg { w.append(wr) }
        w.append(contentsOf: projection.avgPath.map(\.1))
        return w
    }
    private var yMin: Double { (allWeightsKg.min().map { display($0) } ?? 0) - 1.5 }
    private var yMax: Double { (allWeightsKg.max().map { display($0) } ?? 100) + 1.5 }

    var body: some View {
        Chart {
            RuleMark(y: .value("Target", display(active.targetWeightKg)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .foregroundStyle(.gray)

            ForEach(inCutReadings, id: \.id) { r in
                LineMark(
                    x: .value("Date", r.date),
                    y: .value("Weight", display(r.weightKg)),
                    series: .value("series", "actual")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(.primary)

                PointMark(
                    x: .value("Date", r.date),
                    y: .value("Weight", display(r.weightKg))
                )
                .symbolSize(14)
                .foregroundStyle(.primary)
            }

            if !projection.isTargetReached {
                if let bestEnd = projection.bestEndKg {
                    LineMark(
                        x: .value("Date", active.startDate),
                        y: .value("Weight", display(active.startWeightKg)),
                        series: .value("series", "best")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Self.bestColor)
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Date", projection.anchorDate),
                        y: .value("Weight", display(projection.anchorKg)),
                        series: .value("series", "best")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Self.bestColor)
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Date", projection.targetEndDate),
                        y: .value("Weight", display(bestEnd)),
                        series: .value("series", "best")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Self.bestColor)
                    .interpolationMethod(.linear)
                }

                if let worstEnd = projection.worstEndKg {
                    LineMark(
                        x: .value("Date", active.startDate),
                        y: .value("Weight", display(active.startWeightKg)),
                        series: .value("series", "worst")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Self.worstColor)
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Date", projection.anchorDate),
                        y: .value("Weight", display(projection.anchorKg)),
                        series: .value("series", "worst")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Self.worstColor)
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Date", projection.targetEndDate),
                        y: .value("Weight", display(worstEnd)),
                        series: .value("series", "worst")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Self.worstColor)
                    .interpolationMethod(.linear)
                }

                // Avg path with wiggle (linear, NOT smoothed), anchored at cut start
                LineMark(
                    x: .value("Date", active.startDate),
                    y: .value("Weight", display(active.startWeightKg)),
                    series: .value("series", "avg")
                )
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(Self.avgColor)

                ForEach(Array(projection.avgPath.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.0),
                        y: .value("Weight", display(point.1)),
                        series: .value("series", "avg")
                    )
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(Self.avgColor)
                }
            }

            PointMark(
                x: .value("Date", projection.anchorDate),
                y: .value("Weight", display(projection.anchorKg))
            )
            .symbolSize(64)
            .symbol(.circle)
            .foregroundStyle(Color(.systemBackground))

            PointMark(
                x: .value("Date", projection.anchorDate),
                y: .value("Weight", display(projection.anchorKg))
            )
            .symbolSize(64)
            .symbol(.circle.strokeBorder(lineWidth: 2))
            .foregroundStyle(Self.avgColor)

            if projection.isTargetReached {
                PointMark(
                    x: .value("Date", projection.anchorDate),
                    y: .value("Weight", display(projection.anchorKg))
                )
                .symbolSize(0)
                .annotation(position: .top, alignment: .center, spacing: 2) {
                    Text("Target reached")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .chartXScale(domain: active.startDate...active.targetEndDate)
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            if hideXAxisLabels {
                AxisMarks(values: .automatic) { _ in AxisGridLine() }
            } else {
                AxisMarks(values: [active.startDate, projection.anchorDate, active.targetEndDate]) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: height)
    }
}
