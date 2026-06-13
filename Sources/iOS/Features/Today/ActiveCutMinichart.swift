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
    let milestones: [Milestone]
    let allReadings: [Reading]

    init(
        active: ActiveCut,
        inCutReadings: [Reading],
        projection: CutProjectionResult,
        unit: WeightUnit,
        milestones: [Milestone] = [],
        allReadings: [Reading] = []
    ) {
        self.active = active
        self.inCutReadings = inCutReadings
        self.projection = projection
        self.unit = unit
        self.milestones = milestones
        // `allReadings` (history including pre-cut) feeds the milestone
        // projector, which needs the full series for its EWMA seed. Caller
        // can omit it for back-compat — projector will skip milestones.
        self.allReadings = allReadings.isEmpty ? inCutReadings : allReadings
    }

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
        // Extend the visible window to include the furthest upcoming
        // milestone so its dot doesn't fall off the right edge. Capped at
        // the cut's target end date — we never project past the cut.
        let furthestMilestone = upcomingMilestones.map(\.date).max()
        let baseEnd = max(fourteenDaysOut, furthestMilestone ?? fourteenDaysOut)
        return min(active.targetEndDate, baseEnd)
    }

    /// Upcoming milestones inside this cut window, sorted oldest-first.
    private var upcomingMilestones: [Milestone] {
        let today = Calendar.current.startOfDay(for: Date())
        return milestones
            .filter { $0.date >= today && $0.date <= active.targetEndDate }
            .sorted { $0.date < $1.date }
    }

    /// Projected kg at each upcoming milestone; `nil` entries are dropped so
    /// the chart skips milestones whose projection is unavailable (too few
    /// readings, band too wide). The projector reuses the same EWMA seed
    /// and trend as the rest of the system — milestones share the truth.
    private var milestonePoints: [(milestone: Milestone, projectedKg: Double)] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        return upcomingMilestones.compactMap { m in
            let days = max(1, cal.dateComponents([.day], from: today, to: m.date).day ?? 1)
            guard let result = CutWeightProjector.project(
                activeCut: active,
                readings: allReadings,
                horizonDays: days,
                asOf: now
            ), !result.isFlat else {
                return nil
            }
            return (m, result.projectedKg)
        }
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
        // Include milestone projections so the y-axis autoscale doesn't
        // clip them — a milestone weight below the current data range
        // would otherwise sit off-screen.
        w.append(contentsOf: milestonePoints.map(\.projectedKg))
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
        .accessibilityLabel("Active cut chart. Rotate to landscape for a focused view.")
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

            // Milestone dots with floating name labels. Each dot anchors at
            // the milestone's date + projected weight; the annotation floats
            // above with the milestone name to motivate the user — "this is
            // where you'll be by your trip".
            ForEach(milestonePoints, id: \.milestone.id) { entry in
                PointMark(
                    x: .value("Milestone Date", entry.milestone.date),
                    y: .value("Milestone Weight", display(entry.projectedKg))
                )
                .symbolSize(70)
                .symbol(.circle)
                .foregroundStyle(Color.accentColor)
                .annotation(position: .top, alignment: .center, spacing: 3) {
                    Text(entry.milestone.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color(.systemBackground).opacity(0.85))
                        )
                        .lineLimit(1)
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
}
