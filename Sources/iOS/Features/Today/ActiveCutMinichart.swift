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

    private static let avgColor: Color = .primary
    private static let bestColor: Color = .green
    private static let worstColor: Color = Color(red: 0.78, green: 0.30, blue: 0.30)

    private func display(_ kg: Double) -> Double {
        UnitConvert.displayWeight(kg: kg, in: unit)
    }

    private static let secondsPerDay: TimeInterval = 86_400

    private var windowEnd: Date {
        let fourteenDaysOut = projection.anchorDate.addingTimeInterval(14 * Self.secondsPerDay)
        return min(active.targetEndDate, fourteenDaysOut)
    }

    private func interp(from a: (Date, Double), to b: (Date, Double), at t: Date) -> Double {
        let total = b.0.timeIntervalSince(a.0)
        guard total > 0 else { return a.1 }
        let f = max(0, min(1, t.timeIntervalSince(a.0) / total))
        return a.1 + (b.1 - a.1) * f
    }

    private var visibleWeightsKg: [Double] {
        var w = inCutReadings.map(\.weightKg)
        w.append(active.startWeightKg)
        w.append(projection.anchorKg)
        w.append(contentsOf: projection.avgPath.filter { $0.0 <= windowEnd }.map { $0.1 + avgPathShift })
        if let bestEnd = projection.bestEndKg {
            w.append(interp(from: (active.startDate, active.startWeightKg),
                            to: (projection.targetEndDate, bestEnd), at: windowEnd))
        }
        if let worstEnd = projection.worstEndKg {
            w.append(interp(from: (active.startDate, active.startWeightKg),
                            to: (projection.targetEndDate, worstEnd), at: windowEnd))
        }
        return w
    }
    private var yMin: Double { (visibleWeightsKg.min().map { display($0) } ?? 0) - 1.5 }
    private var yMax: Double { (visibleWeightsKg.max().map { display($0) } ?? 100) + 1.5 }

    /// Where the avg line would be at anchorDate if it had been descending at its implied slope
    /// from (startDate, startWeightKg) — keeps best < avg < worst at every date on the chart.
    private var impliedAvgAtAnchorKg: Double {
        guard let avgEnd = projection.avgPath.last?.1 else { return projection.anchorKg }
        let totalDays = active.startDate.distance(to: projection.targetEndDate) / Self.secondsPerDay
        let histDays = active.startDate.distance(to: projection.anchorDate) / Self.secondsPerDay
        guard totalDays > 0 else { return projection.anchorKg }
        let impliedSlope = (avgEnd - active.startWeightKg) / totalDays
        return active.startWeightKg + impliedSlope * histDays
    }

    /// Offset applied to each future avgPath point so it continues from impliedAvgAtAnchorKg.
    private var avgPathShift: Double {
        impliedAvgAtAnchorKg - projection.anchorKg
    }

    var body: some View {
        Button {
            showFullscreen = true
        } label: {
            VStack(spacing: 0) {
                Chart {
                    RuleMark(y: .value("Target", display(active.targetWeightKg)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 6]))
                        .foregroundStyle(.secondary.opacity(0.25))
                        .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                            Text("Target")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }

                    // Gradient fill under actual data — rendered before the lines so they sit on top.
                    // Apple Health-style: saturated blue at the top of the area, fading to transparent at the bottom.
                    ForEach(inCutReadings, id: \.id) { r in
                        AreaMark(
                            x: .value("Date", r.date),
                            y: .value("Weight", display(r.weightKg))
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.blue.opacity(0.38), location: 0.0),
                                    .init(color: Color.blue.opacity(0.18), location: 0.45),
                                    .init(color: Color.blue.opacity(0.0),  location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    // Actual data line + dots
                    ForEach(inCutReadings, id: \.id) { r in
                        LineMark(
                            x: .value("Date", r.date),
                            y: .value("Weight", display(r.weightKg)),
                            series: .value("series", "actual")
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Color.blue)

                        PointMark(
                            x: .value("Date", r.date),
                            y: .value("Weight", display(r.weightKg))
                        )
                        .symbolSize(12)
                        .foregroundStyle(Color.blue)
                    }

                    if !projection.isTargetReached {
                        // Best: dashed green, day 0 → cut end
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
                                x: .value("Date", projection.targetEndDate),
                                y: .value("Weight", display(bestEnd)),
                                series: .value("series", "best")
                            )
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Self.bestColor)
                            .interpolationMethod(.linear)
                        }

                        // Worst: dashed red, day 0 → cut end
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
                                x: .value("Date", projection.targetEndDate),
                                y: .value("Weight", display(worstEnd)),
                                series: .value("series", "worst")
                            )
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Self.worstColor)
                            .interpolationMethod(.linear)
                        }

                        // Avg: dashed black, day 0 → implied-avg-at-today → wiggly future.
                        // Historical segment uses the implied slope so best < avg < worst always.
                        LineMark(
                            x: .value("Date", active.startDate),
                            y: .value("Weight", display(active.startWeightKg)),
                            series: .value("series", "avg")
                        )
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(Self.avgColor)

                        LineMark(
                            x: .value("Date", projection.anchorDate),
                            y: .value("Weight", display(impliedAvgAtAnchorKg)),
                            series: .value("series", "avg")
                        )
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(Self.avgColor)

                        ForEach(Array(projection.avgPath.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Date", point.0),
                                y: .value("Weight", display(point.1 + avgPathShift)),
                                series: .value("series", "avg")
                            )
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Self.avgColor)
                        }
                    }

                    // Today anchor: hollow circle marks current position
                    PointMark(
                        x: .value("Date", projection.anchorDate),
                        y: .value("Weight", display(projection.anchorKg))
                    )
                    .symbolSize(110)
                    .symbol(.circle)
                    .foregroundStyle(Color(.systemBackground))

                    PointMark(
                        x: .value("Date", projection.anchorDate),
                        y: .value("Weight", display(projection.anchorKg))
                    )
                    .symbolSize(110)
                    .symbol(.circle.strokeBorder(lineWidth: 2.5))
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
                .chartXScale(domain: active.startDate...windowEnd)
                .chartYScale(domain: yMin...yMax)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 320)
                .padding(.horizontal, 4)

                // Date labels in a safe gutter below the chart — never overlapping data
                HStack {
                    Text(Self.dateFmt.string(from: active.startDate))
                    Spacer()
                    Text(Self.dateFmt.string(from: windowEnd))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
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
                out.append(.init(name: "Best", style: .projectionDashedGreen, points: [(active.startDate, active.startWeightKg), (projection.targetEndDate, bestEnd)]))
            }
            if let worstEnd = projection.worstEndKg {
                out.append(.init(name: "Worst", style: .projectionDashedRed, points: [(active.startDate, active.startWeightKg), (projection.targetEndDate, worstEnd)]))
            }
            if !projection.avgPath.isEmpty {
                out.append(.init(name: "Avg", style: .projectionSolidBlue, points: [(active.startDate, active.startWeightKg)] + projection.avgPath))
            }
        }
        return out
    }

    private func formatted(_ kg: Double) -> String {
        String(format: "%.1f %@", display(kg), unit.symbol)
    }
}
