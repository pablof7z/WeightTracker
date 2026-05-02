import SwiftUI

struct ActiveCutCard: View {
    let cut: ActiveCut
    let actualRateLbPerWeek: Double?
    let neededRateLbPerWeek: Double?
    let status: CutsViewModel.CutStatus?
    let projectedEndWeightKg: Double?
    let unit: WeightUnit
    var readings: [Reading] = []
    var projection: CutProjectionResult? = nil
    var onMarkDone: () -> Void

    @State private var showFullscreen = false
    @State private var confirmEnd = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Active Cut", systemImage: "scissors")
                    .font(.headline)
                Spacer()
                Text("\(Self.dateFmt.string(from: cut.startDate)) → \(Self.dateFmt.string(from: cut.targetEndDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Cut runs from \(Self.dateFmt.string(from: cut.startDate)) to \(Self.dateFmt.string(from: cut.targetEndDate))")
            }

            HStack(spacing: 16) {
                metric(
                    title: "Days in",
                    value: "\(cut.daysElapsed())"
                )
                metric(
                    title: cut.daysRemaining() < 0 ? "Status" : "Days left",
                    value: cut.daysRemaining() < 0 ? "Overdue" : "\(cut.daysRemaining())"
                )
                metric(
                    title: "Target",
                    value: formatWeight(cut.targetWeightKg)
                )
            }

            HStack(spacing: 16) {
                rateView(
                    title: "Actual",
                    rateLbPerWeek: actualRateLbPerWeek
                )
                rateView(
                    title: "Needed",
                    rateLbPerWeek: neededRateLbPerWeek
                )
                statusBadge
            }

            if let projectedEndWeightKg {
                Text("Projection: \(formatWeight(projectedEndWeightKg)) by \(Self.dateFmt.string(from: cut.targetEndDate))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Group {
                if let projection {
                    CutProjectionChartContent(
                        active: cut,
                        inCutReadings: readings.filter { $0.date >= cut.startDate },
                        projection: projection,
                        unit: unit,
                        height: 140
                    )
                } else {
                    CutInlineChart(
                        readings: readings,
                        startDate: cut.startDate,
                        endDate: max(cut.targetEndDate, Date()),
                        unit: unit,
                        targetWeightKg: cut.targetWeightKg,
                        startWeightKg: cut.startWeightKg
                    )
                }
            }
            .padding(.top, 4)
            .contentShape(Rectangle())
            .onTapGesture { showFullscreen = true }
            .fullScreenCover(isPresented: $showFullscreen) {
                fullscreenChart
            }

            Button {
                confirmEnd = true
            } label: {
                Label("Mark done", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .padding(.top, 4)
            .confirmationDialog("Finish this cut?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End cut", role: .destructive) { onMarkDone() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your progress will be saved as a historical cut if it qualifies. You can start a new cut anytime.")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rateView(title: String, rateLbPerWeek: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let rate = rateLbPerWeek {
                Text("\(formatRate(rate))")
                    .font(.title3).bold()
                    .monospacedDigit()
            } else {
                Text("—").font(.title3).bold()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let resolved: (label: String, color: Color)? = {
            guard let status else { return nil }
            switch status {
            case .onTrack:  return ("On track", .green)
            case .behind:   return ("Behind", .orange)
            case .reversed: return ("Reversed", .red)
            }
        }()
        if let resolved {
            Text(resolved.label)
                .font(.caption).bold()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(resolved.color.opacity(0.18), in: Capsule())
                .foregroundStyle(resolved.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("—")
                .font(.title3).bold()
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatWeight(_ kg: Double) -> String {
        let v = UnitConvert.displayWeight(kg: kg, in: unit)
        return String(format: "%.1f %@", v, unit.symbol)
    }

    private func formatRate(_ lbPerWeek: Double) -> String {
        if unit == .lbs {
            return String(format: "%.1f lb/wk", lbPerWeek)
        } else {
            let kg = UnitConvert.lbToKg(lbPerWeek)
            return String(format: "%.1f kg/wk", kg)
        }
    }

    @ViewBuilder
    private var fullscreenChart: some View {
        let inCut = readings.filter { $0.date >= cut.startDate }
        FullscreenChartView(
            title: "Active Cut",
            subtitle: "\(Self.dateFmt.string(from: cut.startDate)) → \(Self.dateFmt.string(from: cut.targetEndDate))",
            series: buildSeries(inCut: inCut),
            unit: unit,
            targetWeightKg: cut.targetWeightKg
        )
    }

    private func buildSeries(inCut: [Reading]) -> [FullscreenChartView.Series] {
        var out: [FullscreenChartView.Series] = []
        out.append(.init(
            name: "Actual",
            style: .actualSolidPrimary,
            points: inCut.map { ($0.date, $0.weightKg) }
        ))
        if let p = projection, !p.isTargetReached {
            if let bestEnd = p.bestEndKg {
                out.append(.init(name: "Best", style: .projectionDashedGreen, points: [
                    (p.anchorDate, p.anchorKg),
                    (p.targetEndDate, bestEnd)
                ]))
            }
            if let worstEnd = p.worstEndKg {
                out.append(.init(name: "Worst", style: .projectionDashedRed, points: [
                    (p.anchorDate, p.anchorKg),
                    (p.targetEndDate, worstEnd)
                ]))
            }
            if !p.avgPath.isEmpty {
                out.append(.init(name: "Avg", style: .projectionSolidBlue, points: p.avgPath))
            }
        }
        return out
    }
}
