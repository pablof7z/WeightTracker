import SwiftUI
import Charts

extension Notification.Name {
    static let openCutsTab = Notification.Name("openCutsTab")
}

/// Avg path carries deterministic residual wiggle so users see realistic week-to-week variation, not a falsely smooth projection.
struct ActiveCutMinichart: View {
    let active: ActiveCut
    let inCutReadings: [Reading]
    let projection: CutProjectionResult
    let unit: WeightUnit

    @State private var showFullscreen = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let avgColor: Color = .blue
    private static let bestColor: Color = .green
    private static let worstColor: Color = Color(red: 0.78, green: 0.30, blue: 0.30)

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
        Button {
            showFullscreen = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                header

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

                        // Avg path (solid blue with wiggle preserved — linear, NOT catmullRom), anchored at cut start.
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
                    AxisMarks(values: [active.startDate, projection.anchorDate, active.targetEndDate]) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 96)

                footer
            }
            .padding(12)
            .glass(in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Active cut chart. Tap to open fullscreen.")
        .fullScreenCover(isPresented: $showFullscreen) {
            FullscreenChartView(
                title: "Active Cut",
                subtitle: "\(Self.dateFmt.string(from: active.startDate)) → \(Self.dateFmt.string(from: active.targetEndDate))",
                series: buildSeries(),
                unit: unit,
                targetWeightKg: active.targetWeightKg
            )
        }
    }

    private func buildSeries() -> [FullscreenChartView.Series] {
        var out: [FullscreenChartView.Series] = []
        out.append(.init(name: "Actual", style: .actualSolidPrimary, points: inCutReadings.map { ($0.date, $0.weightKg) }))
        if !projection.isTargetReached {
            if let bestEnd = projection.bestEndKg {
                out.append(.init(name: "Best", style: .projectionDashedGreen, points: [(active.startDate, active.startWeightKg), (projection.anchorDate, projection.anchorKg), (projection.targetEndDate, bestEnd)]))
            }
            if let worstEnd = projection.worstEndKg {
                out.append(.init(name: "Worst", style: .projectionDashedRed, points: [(active.startDate, active.startWeightKg), (projection.anchorDate, projection.anchorKg), (projection.targetEndDate, worstEnd)]))
            }
            if !projection.avgPath.isEmpty {
                out.append(.init(name: "Avg", style: .projectionSolidBlue, points: [(active.startDate, active.startWeightKg)] + projection.avgPath))
            }
        }
        return out
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "scissors")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            Text("Active cut")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if projection.isTargetReached {
            Text("Target reached — maintain")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if projection.qualifyingHistoricalCount == 0 {
            Text("Based on typical lean-cut research (no past cuts yet)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let best = projection.bestEndKg,
                  let worst = projection.worstEndKg,
                  let avgEnd = projection.avgPath.last?.1 {
            Text("Best \(formatted(best)) · Avg \(formatted(avgEnd)) · Worst \(formatted(worst)) by \(Self.dateFmt.string(from: projection.targetEndDate))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private func formatted(_ kg: Double) -> String {
        String(format: "%.1f %@", display(kg), unit.symbol)
    }
}
