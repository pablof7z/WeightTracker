import SwiftUI

struct RightNowCard: View {
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    let viewModel: TrendsViewModel

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lbs
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Right now")
                .font(.headline)

            if let recent = viewModel.mostRecent {
                latestRow(recent: recent)
                Divider()
                deltasRow
                if viewModel.activeCluster != nil {
                    Divider()
                    clusterMessage
                } else if viewModel.activeGap != nil {
                    Divider()
                    gapMessage
                }
            } else {
                Text("No readings yet. Log a weight to see trends.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func latestRow(recent: Reading) -> some View {
        let displayValue = UnitConvert.displayWeight(kg: recent.weightKg, in: weightUnit)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatNumber(displayValue) + " " + weightUnit.symbol)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(Self.dateFormatter.string(from: recent.date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(recent.source.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(.tertiarySystemBackground))
                )
                .foregroundStyle(.secondary)
        }
    }

    private var deltasRow: some View {
        HStack(spacing: 12) {
            ForEach(viewModel.deltas(), id: \.label) { d in
                deltaTile(label: d.label, valueLb: d.valueLb)
            }
        }
    }

    private func deltaTile(label: String, valueLb: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let v = valueLb {
                let displayDelta = weightUnit == .lbs ? v : UnitConvert.lbToKg(v)
                let prefix = displayDelta >= 0 ? "+" : ""
                Text("\(prefix)\(formatNumber(displayDelta)) \(weightUnit.symbol)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(deltaColor(displayDelta))
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var clusterMessage: some View {
        if let days = viewModel.clusterDaysIn, let downLb = viewModel.clusterDownLb {
            let downDisplay = weightUnit == .lbs ? downLb : UnitConvert.lbToKg(downLb)
            let prefix = downDisplay >= 0 ? "Down " : "Up "
            let magnitude = formatNumber(abs(downDisplay))
            Text("You're \(days) day\(days == 1 ? "" : "s") into a tracking streak. \(prefix)\(magnitude) \(weightUnit.symbol) from cluster start.")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var gapMessage: some View {
        if let days = viewModel.gapDaysSinceLast, let drift = viewModel.estimatedDriftLb {
            let driftDisplay = weightUnit == .lbs ? drift : UnitConvert.lbToKg(drift)
            let prefix = driftDisplay >= 0 ? "+" : ""
            Text("It's been \(days) day\(days == 1 ? "" : "s") since you last logged. Based on your history, your weight has likely drifted \(prefix)\(formatNumber(driftDisplay)) \(weightUnit.symbol).")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private func deltaColor(_ delta: Double) -> Color {
        guard viewModel.activeCluster?.classification == .cut else { return .secondary }
        return delta >= 0 ? .red : .green
    }

    private func formatNumber(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
