import SwiftUI
import Charts

extension Notification.Name {
    static let openCutsTab = Notification.Name("openCutsTab")
}

/// Compact 100pt-tall chart on the Today screen showing the active cut's trajectory
/// plus required + typical (+ fast band) projections to the target date.
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

    private func display(_ kg: Double) -> Double {
        UnitConvert.displayWeight(kg: kg, in: unit)
    }

    private var typicalRay: CutProjectionRay? {
        projection.rays.first { $0.label == .typical }
    }
    private var fastRay: CutProjectionRay? {
        projection.rays.first { $0.label == .fast }
    }
    private var requiredRay: CutProjectionRay? {
        projection.rays.first { $0.label == .required }
    }

    private var allWeightsKg: [Double] {
        var w = inCutReadings.map(\.weightKg)
        w.append(active.startWeightKg)
        w.append(active.targetWeightKg)
        for r in projection.rays {
            w.append(r.anchorWeightKg)
            w.append(r.endWeightKg)
        }
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
                    // Target line
                    RuleMark(y: .value("Target", display(active.targetWeightKg)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.green.opacity(0.6))

                    // Best/Typical band (only when both rays exist)
                    if let typical = typicalRay, let fast = fastRay {
                        AreaMark(
                            x: .value("AnchorB", typical.anchorDate),
                            yStart: .value("FastY", display(fast.endWeightKg)),
                            yEnd: .value("TypicalY", display(typical.endWeightKg))
                        )
                        AreaMark(
                            x: .value("EndB", typical.endDate),
                            yStart: .value("FastY", display(fast.endWeightKg)),
                            yEnd: .value("TypicalY", display(typical.endWeightKg))
                        )
                    }

                    // Actual readings
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

                    // Typical projection line
                    if let typical = typicalRay {
                        LineMark(
                            x: .value("Date", typical.anchorDate),
                            y: .value("Weight", display(typical.anchorWeightKg)),
                            series: .value("series", "typical")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        LineMark(
                            x: .value("Date", typical.endDate),
                            y: .value("Weight", display(typical.endWeightKg)),
                            series: .value("series", "typical")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.secondary)

                        PointMark(
                            x: .value("End", typical.endDate),
                            y: .value("EndW", display(typical.endWeightKg))
                        )
                        .symbolSize(28)
                        .foregroundStyle(.secondary)
                        .annotation(position: .topTrailing, alignment: .trailing, spacing: 2) {
                            Text(formattedEnd(typical))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Required-pace line (only when no historical data → plays the lead role)
                    if let required = requiredRay, typicalRay == nil {
                        LineMark(
                            x: .value("Date", required.anchorDate),
                            y: .value("Weight", display(required.anchorWeightKg)),
                            series: .value("series", "required")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.green)
                        LineMark(
                            x: .value("Date", required.endDate),
                            y: .value("Weight", display(required.endWeightKg)),
                            series: .value("series", "required")
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.green)
                    }
                }
                .opacity(projection.isOffTrack ? 0.6 : 1.0)
                .chartXScale(domain: active.startDate...active.targetEndDate)
                .chartYScale(domain: yMin...yMax)
                .chartXAxis {
                    AxisMarks(values: [active.startDate, projection.anchorDate, active.targetEndDate]) { val in
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
            if projection.isOffTrack {
                Text("Off-track")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if let typical = typicalRay {
                Text("Typical pace ends \(formattedEnd(typical))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(projection.qualifyingHistoricalCount) past cut\(projection.qualifyingHistoricalCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let required = requiredRay {
                Text("Needs ~\(requiredRateLabel(required)) to hit \(formatted(active.targetWeightKg))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("No past cuts to compare")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formattedEnd(_ ray: CutProjectionRay) -> String {
        "\(formatted(ray.endWeightKg)) by \(Self.dateFmt.string(from: ray.endDate))"
    }
    private func formatted(_ kg: Double) -> String {
        String(format: "%.1f %@", display(kg), unit.symbol)
    }
    private func requiredRateLabel(_ ray: CutProjectionRay) -> String {
        let days = ray.endDate.timeIntervalSince(ray.anchorDate) / 86_400
        guard days > 0 else { return "—" }
        let kgPerDay = (ray.endWeightKg - ray.anchorWeightKg) / days
        let lbPerWeek = abs(UnitConvert.kgToLb(kgPerDay)) * 7.0
        return String(format: "%.1f lb/wk", lbPerWeek)
    }
}
