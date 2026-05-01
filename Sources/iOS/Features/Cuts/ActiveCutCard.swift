import SwiftUI

struct ActiveCutCard: View {
    let cut: ActiveCut
    let actualRateLbPerWeek: Double?
    let neededRateLbPerWeek: Double?
    let status: CutsViewModel.CutStatus?
    let projectedEndWeightKg: Double?
    let unit: WeightUnit
    var onMarkDone: () -> Void

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
            }

            HStack(spacing: 16) {
                metric(
                    title: "Days in",
                    value: "\(cut.daysElapsed())"
                )
                metric(
                    title: "Days left",
                    value: "\(cut.daysRemaining())"
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

            Button(role: .destructive, action: onMarkDone) {
                Label("Mark done", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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
        if let status {
            let (label, color): (String, Color) = {
                switch status {
                case .onTrack: return ("On track", .green)
                case .behind: return ("Behind", .orange)
                case .reversed: return ("Reversed", .red)
                }
            }()
            Text(label)
                .font(.caption).bold()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(color.opacity(0.18), in: Capsule())
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
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
}
