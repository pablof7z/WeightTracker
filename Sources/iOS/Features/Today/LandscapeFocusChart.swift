import SwiftUI
import Charts

/// Landscape-only "focus" chart for the Today tab.
///
/// Reuses the same data series and visual treatment as `ActiveCutMinichart`
/// (black actual line + projection lines + the `chartBackground`-driven
/// gradient fill that fades from solid black under the readings down to
/// transparent at the plot bottom), but exposes interactions: tap-to-inspect
/// (vertical rule + value pill), a window selector for the visible X domain,
/// and a double-tap-to-reset.
///
/// Designed to be presented bleed-edge — caller hides the tab bar and the
/// container ignores all safe areas.
struct LandscapeFocusChart: View {
    let active: ActiveCut
    let inCutReadings: [Reading]
    let projection: CutProjectionResult
    let unit: WeightUnit

    enum Window: String, CaseIterable, Identifiable {
        case all = "All"
        case last30 = "30d"
        case last14 = "14d"
        case last7 = "7d"
        case next14 = "+14d"
        var id: String { rawValue }
    }

    @State private var window: Window = .all
    @State private var selectedDate: Date?

    private static let secondsPerDay: TimeInterval = 86_400

    private static let pillFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let avgColor: Color = .primary
    private static let bestColor: Color = .green
    private static let worstColor: Color = Color(red: 0.78, green: 0.30, blue: 0.30)

    private func display(_ kg: Double) -> Double {
        UnitConvert.displayWeight(kg: kg, in: unit)
    }

    // MARK: - Domain (X)

    private var fullStart: Date { active.startDate }
    private var fullEnd: Date {
        // Show readings through projection-anchor + 14 days, capped at the
        // cut target end date. Same windowing as the minichart.
        let twoWeeksOut = projection.anchorDate.addingTimeInterval(14 * Self.secondsPerDay)
        return min(active.targetEndDate, twoWeeksOut)
    }

    private var xDomain: ClosedRange<Date> {
        let now = projection.anchorDate
        switch window {
        case .all:
            return fullStart...fullEnd
        case .last30:
            let start = max(fullStart, now.addingTimeInterval(-30 * Self.secondsPerDay))
            return start...now
        case .last14:
            let start = max(fullStart, now.addingTimeInterval(-14 * Self.secondsPerDay))
            return start...now
        case .last7:
            let start = max(fullStart, now.addingTimeInterval(-7 * Self.secondsPerDay))
            return start...now
        case .next14:
            let end = min(fullEnd, now.addingTimeInterval(14 * Self.secondsPerDay))
            return now...end
        }
    }

    // MARK: - Domain (Y, autoscaled to visible window)

    private var visibleWeightsKg: [Double] {
        let domain = xDomain
        var w: [Double] = []
        for r in inCutReadings where domain.contains(r.date) {
            w.append(r.weightKg)
        }
        if domain.contains(active.startDate) { w.append(active.startWeightKg) }
        if domain.contains(projection.anchorDate) { w.append(projection.anchorKg) }
        for p in projection.avgPath where domain.contains(p.0) {
            w.append(p.1 + avgPathShift)
        }
        if let bestEnd = projection.bestEndKg, domain.contains(projection.targetEndDate) {
            w.append(bestEnd)
        }
        if let worstEnd = projection.worstEndKg, domain.contains(projection.targetEndDate) {
            w.append(worstEnd)
        }
        // Defensive fallback when the window contains nothing
        if w.isEmpty {
            w = inCutReadings.map(\.weightKg)
            if w.isEmpty { w = [active.startWeightKg, active.targetWeightKg] }
        }
        return w
    }

    private var yMin: Double {
        let lo = visibleWeightsKg.min().map { display($0) } ?? 0
        let hi = visibleWeightsKg.max().map { display($0) } ?? 100
        let range = max(hi - lo, 1.0)
        return lo - max(1.5, range * 0.12)
    }
    private var yMax: Double {
        let hi = visibleWeightsKg.max().map { display($0) } ?? 100
        let lo = visibleWeightsKg.min().map { display($0) } ?? 0
        let range = max(hi - lo, 1.0)
        return hi + max(1.5, range * 0.08)
    }

    // Same implied-avg shift the minichart uses, so the avg dashed line is
    // continuous through the anchor in the focus chart too.
    private var impliedAvgAtAnchorKg: Double {
        guard let avgEnd = projection.avgPath.last?.1 else { return projection.anchorKg }
        let totalDays = active.startDate.distance(to: projection.targetEndDate) / Self.secondsPerDay
        let histDays = active.startDate.distance(to: projection.anchorDate) / Self.secondsPerDay
        guard totalDays > 0 else { return projection.anchorKg }
        let impliedSlope = (avgEnd - active.startWeightKg) / totalDays
        return active.startWeightKg + impliedSlope * histDays
    }
    private var avgPathShift: Double { impliedAvgAtAnchorKg - projection.anchorKg }

    // MARK: - Selection helper

    private func nearestReading(to date: Date) -> Reading? {
        inCutReadings.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    var body: some View {
        ZStack {
            // True bleed-edge background
            Color(.systemBackground)
                .ignoresSafeArea()

            chartBody
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .ignoresSafeArea()

            // Floating window picker, bottom-center, unobtrusive.
            VStack {
                Spacer()
                Picker("Window", selection: $window) {
                    ForEach(Window.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glass(in: Capsule())
                .padding(.bottom, 12)
            }
            .ignoresSafeArea(.keyboard)

            // Selection pill — placed near the top so it doesn't conflict
            // with the picker.
            if let sel = selectedDate, let near = nearestReading(to: sel) {
                VStack {
                    selectionPill(date: near.date, kg: near.weightKg)
                        .padding(.top, 8)
                    Spacer()
                }
                .ignoresSafeArea(.keyboard)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double-tap resets window + selection.
            window = .all
            selectedDate = nil
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartBody: some View {
        Chart {
            // Target reference
            RuleMark(y: .value("Target", display(active.targetWeightKg)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 6]))
                .foregroundStyle(.secondary.opacity(0.35))
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text("Target \(String(format: "%.1f", display(active.targetWeightKg))) \(unit.symbol)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

            // Actual readings — black line + dots, same as minichart.
            ForEach(inCutReadings, id: \.id) { r in
                LineMark(
                    x: .value("Date", r.date),
                    y: .value("Weight", display(r.weightKg)),
                    series: .value("series", "actual")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .foregroundStyle(Color.primary)

                PointMark(
                    x: .value("Date", r.date),
                    y: .value("Weight", display(r.weightKg))
                )
                .symbolSize(18)
                .foregroundStyle(Color.primary)
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
                        x: .value("Date", projection.targetEndDate),
                        y: .value("Weight", display(worstEnd)),
                        series: .value("series", "worst")
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Self.worstColor)
                    .interpolationMethod(.linear)
                }

                // Avg dashed (implied historical → wiggly future).
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

                ForEach(Array(projection.avgPath.enumerated()), id: \.offset) { _, p in
                    LineMark(
                        x: .value("Date", p.0),
                        y: .value("Weight", display(p.1 + avgPathShift)),
                        series: .value("series", "avg")
                    )
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Self.avgColor)
                }
            }

            // Today anchor
            PointMark(
                x: .value("Date", projection.anchorDate),
                y: .value("Weight", display(projection.anchorKg))
            )
            .symbolSize(140)
            .symbol(.circle)
            .foregroundStyle(Color(.systemBackground))

            PointMark(
                x: .value("Date", projection.anchorDate),
                y: .value("Weight", display(projection.anchorKg))
            )
            .symbolSize(140)
            .symbol(.circle.strokeBorder(lineWidth: 2.5))
            .foregroundStyle(Self.avgColor)

            // Selection rule + dot
            if let sel = selectedDate, let near = nearestReading(to: sel) {
                RuleMark(x: .value("sel", near.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.secondary.opacity(0.45))

                PointMark(
                    x: .value("sel", near.date),
                    y: .value("selW", display(near.weightKg))
                )
                .symbolSize(80)
                .symbol(.circle)
                .foregroundStyle(.primary)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yMin...yMax)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v.rounded())) \(unit.symbol)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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

    /// Same path strategy as `ActiveCutMinichart`: trace the readings across
    /// the plot rect and close down to the bottom edge, so the gradient
    /// fades full-height regardless of where the data sits.
    private func areaFillPath(in plotFrame: CGRect, proxy: ChartProxy) -> Path {
        var path = Path()
        let domain = xDomain
        let visible = inCutReadings.filter { domain.contains($0.date) }
        guard !visible.isEmpty else { return path }

        let bottomY = plotFrame.maxY
        let leftX = plotFrame.minX

        let firstX = (proxy.position(forX: visible.first!.date) ?? 0) + leftX
        path.move(to: CGPoint(x: firstX, y: bottomY))

        for r in visible {
            let px = (proxy.position(forX: r.date) ?? 0) + leftX
            let py = (proxy.position(forY: display(r.weightKg)) ?? 0) + plotFrame.minY
            path.addLine(to: CGPoint(x: px, y: py))
        }

        let lastX = (proxy.position(forX: visible.last!.date) ?? 0) + leftX
        path.addLine(to: CGPoint(x: lastX, y: bottomY))
        path.closeSubpath()
        return path
    }

    // MARK: - Selection pill

    private func selectionPill(date: Date, kg: Double) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color.primary).frame(width: 8, height: 8)
            Text(Self.pillFmt.string(from: date))
                .font(.caption.weight(.semibold))
            Text("·")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f %@", display(kg), unit.symbol))
                .font(.caption.bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glass(in: Capsule())
    }
}
