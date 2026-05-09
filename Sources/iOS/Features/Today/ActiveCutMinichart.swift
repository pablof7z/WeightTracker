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
    /// Lower-bounds the chart well below the data so the gradient under the AreaMark
    /// has real vertical distance to fade across — otherwise Swift Charts maps the
    /// gradient to the AreaMark's tight bounding box and the fade looks uniformly grey.
    private var yMin: Double {
        let lo = visibleWeightsKg.min().map { display($0) } ?? 0
        let hi = visibleWeightsKg.max().map { display($0) } ?? 100
        let range = max(hi - lo, 1.0)
        return lo - max(1.5, range * 0.15)
    }
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
                // Date labels in a safe gutter ABOVE the chart so they remain visible
                // even when the chart bleeds behind the tab bar.
                HStack {
                    Text(Self.dateFmt.string(from: active.startDate))
                    Spacer()
                    Text(Self.dateFmt.string(from: windowEnd))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

                chartBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 4)
                    .ignoresSafeArea(.container, edges: .bottom)
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

    /// Chart body extracted so the parent button can size it with `maxHeight: .infinity`
    /// instead of a fixed 320pt frame, letting the chart fill the dead area below
    /// the cut progress strip and bleed behind the tab bar.
    ///
    /// The under-line gradient fill is drawn via `.chartBackground` rather than an
    /// `AreaMark` + `LinearGradient` because Swift Charts maps the AreaMark's
    /// gradient to its tight data hull — when readings hug the top of the plot,
    /// the gradient compresses into a few points of vertical space and reads as
    /// a near-uniform grey block. Tracing the data to a `Path` and filling a
    /// `Rectangle` clipped to that path lets the gradient span the full plot
    /// rect, so the fade is always visible.
    @ViewBuilder
    private var chartBody: some View {
        Chart {
            RuleMark(y: .value("Target", display(active.targetWeightKg)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 6]))
                .foregroundStyle(.secondary.opacity(0.25))
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text("Target")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
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
                .foregroundStyle(Color.primary)

                PointMark(
                    x: .value("Date", r.date),
                    y: .value("Weight", display(r.weightKg))
                )
                .symbolSize(12)
                .foregroundStyle(Color.primary)
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
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame.map({ geo[$0] }) {
                    areaFillPath(in: plotFrame, proxy: proxy)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .primary.opacity(0.55), location: 0.0),
                                    .init(color: .primary.opacity(0.18), location: 0.40),
                                    .init(color: .primary.opacity(0.0),  location: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
    }

    /// Builds a closed `Path` that follows the actual readings across the plot
    /// rect and closes down to its bottom edge — the shape that the gradient
    /// fills. Coordinates are in the GeometryReader's local space, with the
    /// plot rect already offset.
    private func areaFillPath(in plotFrame: CGRect, proxy: ChartProxy) -> Path {
        var path = Path()
        guard !inCutReadings.isEmpty else { return path }

        let bottomY = plotFrame.maxY
        let leftX = plotFrame.minX

        // Start at the bottom-left of the plot under the first reading's x.
        let firstX = (proxy.position(forX: inCutReadings.first!.date) ?? 0) + leftX
        path.move(to: CGPoint(x: firstX, y: bottomY))

        // Trace up to each reading, then across.
        for r in inCutReadings {
            let px = (proxy.position(forX: r.date) ?? 0) + leftX
            let py = (proxy.position(forY: display(r.weightKg)) ?? 0) + plotFrame.minY
            path.addLine(to: CGPoint(x: px, y: py))
        }

        // Close back down to the bottom edge under the last reading.
        let lastX = (proxy.position(forX: inCutReadings.last!.date) ?? 0) + leftX
        path.addLine(to: CGPoint(x: lastX, y: bottomY))
        path.closeSubpath()
        return path
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
