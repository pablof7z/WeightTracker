import SwiftUI
import Charts

struct CutInlineChart: View {
    let readings: [Reading]
    let startDate: Date
    let endDate: Date
    let unit: WeightUnit
    var targetWeightKg: Double? = nil
    var startWeightKg: Double? = nil

    private var inWindow: [Reading] {
        readings.filter { $0.date >= startDate && $0.date <= endDate }
    }

    private func display(_ kg: Double) -> Double {
        UnitConvert.displayWeight(kg: kg, in: unit)
    }

    private var anchors: [Double] {
        var a = inWindow.map(\.weightKg)
        if let s = startWeightKg { a.append(s) }
        if let t = targetWeightKg { a.append(t) }
        return a
    }

    private var yMin: Double {
        guard let m = anchors.min() else { return 0 }
        return floor(display(m) - 1.5)
    }

    private var yMax: Double {
        guard let m = anchors.max() else { return 100 }
        return ceil(display(m) + 1.5)
    }

    var body: some View {
        if inWindow.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No readings in this period")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            Chart {
                if let s = startWeightKg {
                    RuleMark(y: .value("Start", display(s)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.gray.opacity(0.6))
                }
                if let t = targetWeightKg {
                    RuleMark(y: .value("Target", display(t)))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.green)
                }

                ForEach(inWindow, id: \.id) { r in
                    PointMark(
                        x: .value("Date", r.date),
                        y: .value("Weight", display(r.weightKg))
                    )
                    .symbol(.circle)
                    .symbolSize(16)
                    .foregroundStyle(WTColor.dailyDot)
                }

                if inWindow.count >= 2 {
                    ForEach(inWindow, id: \.id) { r in
                        LineMark(
                            x: .value("Date", r.date),
                            y: .value("Weight", display(r.weightKg))
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .foregroundStyle(WTColor.avgLine.opacity(0.6))
                    }
                }
            }
            .chartXScale(domain: startDate...endDate)
            .chartYScale(domain: yMin...yMax)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v.rounded())) \(unit.symbol)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 120)
        }
    }
}
