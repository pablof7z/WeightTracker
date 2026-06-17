import SwiftUI
import Charts

/// Landscape-only "focus" chart for the Today tab.
///
/// Reuses the same data series and visual treatment as `ActiveCutMinichart`
/// (black actual line + projection lines + the `chartBackground`-driven
/// gradient fill that fades from solid black under the readings down to
/// transparent at the plot bottom), but exposes interactions: tap-to-inspect
/// (vertical rule + value pill), a window selector for the visible X domain,
/// pan/pinch to navigate through time freely, and a double-tap-to-reset.
///
/// Designed to be presented bleed-edge — caller hides the tab bar and the
/// container ignores all safe areas.
struct LandscapeFocusChart: View {
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
        self.allReadings = allReadings.isEmpty ? inCutReadings : allReadings
    }

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

    // Pan / pinch navigation
    @State private var panOffset: TimeInterval = 0
    @State private var lastDragX: CGFloat = 0
    @State private var spanDays: Double? = nil
    @State private var spanAtPinchStart: Double? = nil
    @State private var chartWidth: CGFloat = 800

    private var isCustomWindow: Bool { spanDays != nil || panOffset != 0 }

    private static let secondsPerDay: TimeInterval = 86_400

    private static let pillFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let rangeShortFmt: DateFormatter = {
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

    private var smoothedLine: [(date: Date, kg: Double)] {
        let n = inCutReadings.count
        guard n > 0 else { return [] }
        return inCutReadings.enumerated().map { i, r in
            let lo = max(0, i - 2)
            let hi = min(n - 1, i + 2)
            let slice = inCutReadings[lo...hi]
            let avg = slice.reduce(0.0) { $0 + $1.weightKg } / Double(slice.count)
            return (r.date, avg)
        }
    }

    // MARK: - Domain (X)

    private var fullStart: Date { active.startDate }
    private var fullEnd: Date {
        // Show readings through projection-anchor + 14 days, capped at the
        // cut target end date. Same windowing as the minichart, but
        // extended to include the furthest upcoming milestone so a trip in
        // 6 weeks still appears on the .all window.
        let twoWeeksOut = projection.anchorDate.addingTimeInterval(14 * Self.secondsPerDay)
        let furthestMilestone = upcomingMilestones.map(\.date).max()
        let baseEnd = max(twoWeeksOut, furthestMilestone ?? twoWeeksOut)
        return min(active.targetEndDate, baseEnd)
    }

    /// Upcoming milestones inside this cut window, sorted oldest-first.
    private var upcomingMilestones: [Milestone] {
        let today = Calendar.current.startOfDay(for: Date())
        return milestones
            .filter { $0.date >= today && $0.date <= active.targetEndDate }
            .sorted { $0.date < $1.date }
    }

    /// Same projection lookup as the minichart — kept private to each view
    /// rather than shared via a free function, because Charts views compose
    /// best when their data is local. Computational cost is small (one OLS
    /// per milestone) and only runs when milestones exist.
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

    /// Base domain driven purely by the window preset (no pan/span applied).
    private var baseDomain: (start: Date, end: Date) {
        let now = projection.anchorDate
        switch window {
        case .all:
            return (fullStart, fullEnd)
        case .last30:
            return (max(fullStart, now.addingTimeInterval(-30 * Self.secondsPerDay)), now)
        case .last14:
            return (max(fullStart, now.addingTimeInterval(-14 * Self.secondsPerDay)), now)
        case .last7:
            return (max(fullStart, now.addingTimeInterval(-7 * Self.secondsPerDay)), now)
        case .next14:
            return (now, min(fullEnd, now.addingTimeInterval(14 * Self.secondsPerDay)))
        }
    }

    private var xDomain: ClosedRange<Date> {
        let base = baseDomain
        let baseDuration = base.end.timeIntervalSince(base.start)
        let duration = spanDays.map { $0 * Self.secondsPerDay } ?? baseDuration

        var end = base.end.addingTimeInterval(panOffset)
        var start = end.addingTimeInterval(-duration)

        // Clamp so the window never escapes the full data range.
        if start < fullStart {
            start = fullStart
            end = start.addingTimeInterval(duration)
        }
        if end > fullEnd {
            end = fullEnd
            start = end.addingTimeInterval(-duration)
        }
        start = max(fullStart, start)
        end = min(fullEnd, end)

        guard start < end else { return base.start...base.end }
        return start...end
    }

    private var windowLabel: String {
        if !isCustomWindow { return window.rawValue }
        let domain = xDomain
        let fmt = Self.rangeShortFmt
        return "\(fmt.string(from: domain.lowerBound)) – \(fmt.string(from: domain.upperBound))"
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
        // Include milestone projections that fall within the current window
        // so their dots aren't clipped by the y-axis.
        for entry in milestonePoints where domain.contains(entry.milestone.date) {
            w.append(entry.projectedKg)
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

    // MARK: - Window stats

    private struct WindowStats {
        let label: String
        let startWeight: Double
        let endWeight: Double
        let delta: Double
        let pct: Double
        let isProjected: Bool
    }

    /// Linear interpolation along the avg projection path, in display units.
    private func projectedWeight(at date: Date) -> Double? {
        guard !projection.avgPath.isEmpty else { return nil }
        let path = projection.avgPath
        if date <= path[0].0 { return display(path[0].1 + avgPathShift) }
        if date >= path[path.count - 1].0 { return display(path[path.count - 1].1 + avgPathShift) }
        for i in 0..<path.count - 1 {
            let (d0, w0) = path[i]
            let (d1, w1) = path[i + 1]
            if date >= d0 && date <= d1 {
                let t = date.timeIntervalSince(d0) / d1.timeIntervalSince(d0)
                return display(w0 + t * (w1 - w0) + avgPathShift)
            }
        }
        return nil
    }

    private var windowStats: WindowStats? {
        let domain = xDomain
        let now = projection.anchorDate
        let domainHasFuture = domain.upperBound > now
        let visible = inCutReadings.filter { domain.contains($0.date) }

        let startW: Double
        let endW: Double
        let isProjected: Bool

        if domainHasFuture && visible.isEmpty {
            // Pure future window — start at today's anchor, end at projection
            startW = display(projection.anchorKg)
            guard let projEnd = projectedWeight(at: domain.upperBound) else { return nil }
            endW = projEnd
            isProjected = true
        } else if let first = visible.first, let last = visible.last {
            startW = display(first.weightKg)
            if domainHasFuture && !projection.isTargetReached,
               let projEnd = projectedWeight(at: domain.upperBound) {
                endW = projEnd
                isProjected = true
            } else {
                endW = display(last.weightKg)
                isProjected = false
            }
        } else {
            return nil
        }

        let delta = endW - startW
        let pct = startW > 0 ? (delta / startW) * 100.0 : 0
        return WindowStats(
            label: windowLabel,
            startWeight: startW,
            endWeight: endW,
            delta: delta,
            pct: pct,
            isProjected: isProjected
        )
    }

    // MARK: - Gesture handlers

    private func handlePanChanged(_ value: DragGesture.Value) {
        let delta = value.translation.width - lastDragX
        lastDragX = value.translation.width
        let domain = xDomain
        let secondsPerPoint = domain.upperBound.timeIntervalSince(domain.lowerBound) / Double(chartWidth)
        // Drag left → window moves forward; drag right → backward.
        panOffset -= Double(delta) * secondsPerPoint
    }

    private func handlePanEnded(_: DragGesture.Value) {
        lastDragX = 0
        guard spanDays == nil else { return }
        // Snap to "ending today" if the window's upper bound is very close.
        let domain = xDomain
        let distanceFromToday = abs(projection.anchorDate.timeIntervalSince(domain.upperBound))
        if distanceFromToday < 2 * Self.secondsPerDay {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                panOffset = 0
            }
        }
    }

    private func handlePinchChanged(_ scale: CGFloat) {
        if spanAtPinchStart == nil {
            let d = xDomain
            spanAtPinchStart = d.upperBound.timeIntervalSince(d.lowerBound) / Self.secondsPerDay
        }
        let base = spanAtPinchStart ?? 7.0
        // Pinch-in (scale > 1) narrows span; pinch-out widens — matches map behavior.
        spanDays = max(3, min(180, base / Double(scale)))
    }

    private func handlePinchEnded() {
        spanAtPinchStart = nil
        guard let span = spanDays else { return }
        let presets: [Double] = [7, 14, 30]
        guard let nearest = presets.min(by: { abs($0 - span) < abs($1 - span) }),
              abs(nearest - span) / nearest < 0.10 else { return }
        let snapped: Window = nearest == 7 ? .last7 : nearest == 14 ? .last14 : .last30
        withAnimation(.spring(response: 0.3)) {
            spanDays = nil
            window = snapped
            panOffset = 0
        }
    }

    // MARK: - Body

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

            // Stats card — top leading, dims when tap-inspecting a point
            VStack {
                HStack(alignment: .top) {
                    if let stats = windowStats {
                        statsCard(stats)
                            .padding(.leading, 56)
                            .padding(.top, 16)
                    }
                    Spacer()
                }
                Spacer()
            }
            .opacity(selectedDate != nil ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: selectedDate != nil)
            .ignoresSafeArea(.keyboard)

            // Floating window picker, bottom-center, unobtrusive.
            // Dims in custom (pan/pinch) mode; tap any preset to snap back.
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
                .opacity(isCustomWindow ? 0.45 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isCustomWindow)
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
        .background(
            // Capture the view's rendered width for gesture → time conversion.
            GeometryReader { geo in
                Color.clear.onAppear { chartWidth = geo.size.width }
            }
        )
        .simultaneousGesture(
            // minimumDistance:20 keeps tap-to-inspect alive for stationary touches.
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onChanged { handlePanChanged($0) }
                .onEnded   { handlePanEnded($0) }
        )
        .simultaneousGesture(
            MagnificationGesture(minimumScaleDelta: 0.05)
                .onChanged { handlePinchChanged($0) }
                .onEnded   { _ in handlePinchEnded() }
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double-tap resets everything to the default full view.
            withAnimation(.spring(response: 0.35)) {
                window = .all
                panOffset = 0
                spanDays = nil
                selectedDate = nil
            }
        }
        .onChange(of: window) { _, _ in
            // Tapping a preset pill snaps pan and custom span back to zero.
            withAnimation(.easeInOut(duration: 0.2)) {
                panOffset = 0
                spanDays = nil
            }
        }
    }

    // MARK: - Stats card

    @ViewBuilder
    private func statsCard(_ stats: WindowStats) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stats.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            HStack(spacing: 3) {
                Text(String(format: "%.1f", stats.startWeight))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f", stats.endWeight))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if stats.isProjected {
                    Text("~")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 4) {
                Text(String(format: "%+.1f %@", stats.delta, unit.symbol))
                Text("·").foregroundStyle(.tertiary)
                Text(String(format: "%+.1f%%", stats.pct))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(stats.delta <= 0 ? Color.green : Self.worstColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glass(in: RoundedRectangle(cornerRadius: 12))
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

            // Smooth trend line (EWMA) + raw reading dots
            ForEach(Array(smoothedLine.enumerated()), id: \.offset) { _, p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Weight", display(p.kg)),
                    series: .value("series", "actual")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .foregroundStyle(Color.primary)
            }

            ForEach(Array(smoothedLine.enumerated()), id: \.offset) { _, p in
                PointMark(
                    x: .value("Date", p.date),
                    y: .value("Weight", display(p.kg))
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

            // Milestone dots with floating name labels (landscape variant).
            // Larger dots and labels than the minichart to fit the bigger
            // canvas; still capped at 1-line.
            ForEach(milestonePoints, id: \.milestone.id) { entry in
                PointMark(
                    x: .value("Milestone Date", entry.milestone.date),
                    y: .value("Milestone Weight", display(entry.projectedKg))
                )
                .symbolSize(110)
                .symbol(.circle)
                .foregroundStyle(Color.accentColor)
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    Text(entry.milestone.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.systemBackground).opacity(0.85))
                        )
                        .lineLimit(1)
                }
            }

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
        let visible = smoothedLine.filter { domain.contains($0.date) }
        guard !visible.isEmpty else { return path }

        let bottomY = plotFrame.maxY
        let plotLeft = plotFrame.minX

        let pts: [CGPoint] = visible.map { p in
            let px = (proxy.position(forX: p.date) ?? 0) + plotLeft
            let py = (proxy.position(forY: display(p.kg)) ?? 0) + plotFrame.minY
            return CGPoint(x: px, y: py)
        }

        // Extend the fill left past the y-axis and safe-area region so there's no
        // white strip on the left edge in landscape. The gradient is transparent at
        // the bottom so this has no visible effect there; at the data-line height it
        // extends the fill behind the y-axis labels cleanly.
        let fillLeft: CGFloat = 0  // extend to chart view's left edge, covering safe area + y-axis
        path.move(to: CGPoint(x: fillLeft, y: bottomY))
        path.addLine(to: CGPoint(x: fillLeft, y: pts[0].y))
        path.addLine(to: pts[0])

        // Catmull-Rom smooth curve to match the LineMark's .monotone interpolation.
        for i in 1..<pts.count {
            let p0 = i > 1 ? pts[i - 2] : pts[i - 1]
            let p1 = pts[i - 1]
            let p2 = pts[i]
            let p3 = i + 1 < pts.count ? pts[i + 1] : pts[i]
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0, y: p1.y + (p2.y - p0.y) / 6.0)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0, y: p2.y - (p3.y - p1.y) / 6.0)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: bottomY))
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
