import SwiftUI
import Charts

struct WeightChart: View {
    let readings: [Reading]
    let movingAverage: [(date: Date, kg: Double)]
    let clusters: [Cluster]
    let gaps: [Gap]
    let weightUnit: WeightUnit
    let visibleDays: Int
    let showAverage: Bool
    let showClusters: Bool
    let showGaps: Bool

    var body: some View {
        let endDate = readings.last?.date ?? Date()
        let earliest = readings.first?.date ?? endDate.addingTimeInterval(-Double(max(visibleDays, 1)) * 86_400)

        Chart {
            if showClusters {
                ForEach(clusters, id: \.id) { c in
                    RectangleMark(
                        xStart: .value("Start", c.startDate),
                        xEnd: .value("End", c.endDate)
                    )
                    .foregroundStyle(tint(for: c.classification))
                }
            }

            if showGaps {
                ForEach(gaps, id: \.id) { g in
                    RectangleMark(
                        xStart: .value("GapStart", g.startDate),
                        xEnd: .value("GapEnd", g.endDate),
                        yStart: .value("y0", yMin),
                        yEnd: .value("y1", yMin + (yMax - yMin) * 0.05)
                    )
                    .foregroundStyle(WTColor.gapBand)

                    if g.durationDays > 30 {
                        PointMark(
                            x: .value("GapMid", midDate(g.startDate, g.endDate)),
                            y: .value("Label", yMin + (yMax - yMin) * 0.08)
                        )
                        .symbol(.circle)
                        .symbolSize(0)
                        .annotation(position: .overlay) {
                            Text(String(format: "+%.1f lb drift", g.driftLb))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }

            ForEach(readings, id: \.id) { r in
                PointMark(
                    x: .value("Date", r.date),
                    y: .value("Weight", display(r.weightKg))
                )
                .symbol(.circle)
                .symbolSize(20)
                .foregroundStyle(WTColor.dailyDot)
            }

            if showAverage {
                ForEach(Array(movingAverage.enumerated()), id: \.offset) { _, p in
                    LineMark(
                        x: .value("AvgDate", p.date),
                        y: .value("AvgWeight", display(p.kg))
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(WTColor.avgLine)
                }
            }
        }
        .chartXScale(domain: earliest...endDate)
        .chartYScale(domain: yMin...yMax)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainSeconds)
        .chartScrollPosition(initialX: scrollInitialX(end: endDate))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v.rounded())) \(weightUnit.symbol)")
                    }
                }
            }
        }
        .frame(height: 320)
    }

    private func display(_ kg: Double) -> Double {
        UnitConvert.displayWeight(kg: kg, in: weightUnit)
    }

    private var yMin: Double {
        guard !readings.isEmpty else { return 0 }
        let minKg = readings.map(\.weightKg).min() ?? 0
        return floor(display(minKg) - 4)
    }

    private var yMax: Double {
        guard !readings.isEmpty else { return 100 }
        let maxKg = readings.map(\.weightKg).max() ?? 100
        return ceil(display(maxKg) + 4)
    }

    private var visibleDomainSeconds: TimeInterval {
        let days = visibleDays > 0 ? visibleDays : max(30, Calendar.current.dateComponents([.day], from: readings.first?.date ?? Date(), to: readings.last?.date ?? Date()).day ?? 30)
        return Double(days) * 86_400
    }

    private func scrollInitialX(end: Date) -> Date {
        end.addingTimeInterval(-visibleDomainSeconds)
    }

    private func midDate(_ a: Date, _ b: Date) -> Date {
        Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2)
    }

    private func tint(for type: ClusterType) -> Color {
        switch type {
        case .cut: return WTColor.cutTint
        case .bulk: return WTColor.bulkTint
        case .maintenance, .flat: return WTColor.maintTint
        }
    }
}
