import SwiftUI
import Charts

extension Notification.Name {
    static let openCutsTab = Notification.Name("openCutsTab")
}

/// Compact 100pt-tall chart on the Today screen showing the active cut's
/// trajectory plus best/avg/worst projections to the target end date.
///
/// The avg path carries real residual wiggle (deterministic per cut start) so
/// the user can see what realistic week-to-week variation looks like, instead
/// of a falsely smooth line.
struct ActiveCutMinichart: View {
    let active: ActiveCut
    let inCutReadings: [Reading]
    let projection: CutProjectionResult
    let unit: WeightUnit

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
            NotificationCenter.default.post(name: .openCutsTab, object: nil)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                header

                Chart {
                    // Target line (dashed gray).
                    RuleMark(y: .value("Target", display(active.targetWeightKg)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundStyle(.gray)

                    // Actuals (solid line + dots in primary).
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
                        // Best line (dashed green): two endpoints.
                        if let bestEnd = projection.bestEndKg {
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

                        // Worst line (dashed muted red).
                        if let worstEnd = projection.worstEndKg {
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

                        // Avg path (solid blue with wiggle preserved — linear, NOT catmullRom).
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

                    // Anchor donut: white fill + blue stroke (overlay two PointMarks).
                    PointMark(
                        x: .value("Date", projection.anchorDate),
                        y: .value("Weight", display(projection.anchorKg))
                    )
                    .symbolSize(64)
                    .symbol(.circle)
                    .foregroundStyle(.white)

                    PointMark(
                        x: .value("Date", projection.anchorDate),
                        y: .value("Weight", display(projection.anchorKg))
                    )
                    .symbolSize(64)
                    .symbol(.circle.strokeBorder(lineWidth: 2))
                    .foregroundStyle(Self.avgColor)

                    // Target reached annotation.
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
        .accessibilityLabel("Active cut chart. Tap to see full Cut details.")
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
