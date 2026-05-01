import SwiftUI
import Charts

struct DriftBarChart: View {
    let gaps: [Gap]
    let trendLineLb: Double
    var onSelect: (Gap) -> Void

    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drift between clusters")
                .font(.headline)

            if gaps.isEmpty {
                Text("Not enough clusters yet to chart drift between gaps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                chart
                    .frame(height: 220)
                legend
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var chart: some View {
        Chart {
            ForEach(gaps) { gap in
                BarMark(
                    x: .value("Start", gap.startDate, unit: .day),
                    y: .value("Drift (lb)", gap.driftLb)
                )
                .foregroundStyle(gap.didGain ? Color.red : Color.green)
                .annotation(position: .top, alignment: .center) {
                    if selectedID == gap.id {
                        Text(String(format: "%+.1f lb", gap.driftLb))
                            .font(.caption2)
                            .padding(4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            RuleMark(y: .value("Average", trendLineLb))
                .foregroundStyle(WTColor.avgLine)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text(String(format: "Avg %+.1f lb", trendLineLb))
                        .font(.caption2)
                        .foregroundStyle(WTColor.avgLine)
                }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.year())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard let plotFrameAnchor = proxy.plotFrame else { return }
                                let plotFrame = geo[plotFrameAnchor]
                                let xLocal = value.location.x - plotFrame.origin.x
                                guard xLocal >= 0, xLocal <= plotFrame.size.width else { return }
                                if let date: Date = proxy.value(atX: xLocal),
                                   let nearest = nearestGap(to: date) {
                                    selectedID = nearest.id
                                    onSelect(nearest)
                                }
                            }
                    )
            }
        }
    }

    private func nearestGap(to date: Date) -> Gap? {
        gaps.min { lhs, rhs in
            abs(lhs.startDate.timeIntervalSince(date)) < abs(rhs.startDate.timeIntervalSince(date))
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(color: .red, label: "Gain")
            legendDot(color: .green, label: "Loss")
            HStack(spacing: 4) {
                Rectangle()
                    .fill(WTColor.avgLine)
                    .frame(width: 14, height: 2)
                Text("Avg drift")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
