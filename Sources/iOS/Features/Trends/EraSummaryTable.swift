import SwiftUI

struct EraSummaryTable: View {
    let eras: [EraStats]
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRaw) ?? .lbs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eras")
                .font(.headline)

            if eras.isEmpty || eras.allSatisfy({ $0.gapCount == 0 && $0.readingCount == 0 }) {
                Text("Not enough history yet to compare eras.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                header
                Divider()
                ForEach(eras) { era in
                    row(era)
                    if era.id != eras.last?.id { Divider() }
                }
            }
        }
        .padding(16)
        .glass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var header: some View {
        HStack {
            cell("Era", weight: .semibold, align: .leading, width: .infinity)
            cell("Drift", weight: .semibold, align: .trailing, width: 64)
            cell("Rate/mo", weight: .semibold, align: .trailing, width: 70)
            cell("Gaps", weight: .semibold, align: .trailing, width: 44)
            cell("Gain%", weight: .semibold, align: .trailing, width: 54)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func row(_ era: EraStats) -> some View {
        HStack {
            cell(era.label, weight: .regular, align: .leading, width: .infinity)
            cell(signedDelta(lb: era.meanDriftLb),
                 weight: .regular,
                 align: .trailing,
                 width: 64,
                 color: tint(era.meanDriftLb))
            cell(signedDelta(lb: era.meanRateLbPerMonth),
                 weight: .regular,
                 align: .trailing,
                 width: 70,
                 color: tint(era.meanRateLbPerMonth))
            cell("\(era.gapCount)", weight: .regular, align: .trailing, width: 44)
            cell(percent(era.gainRatio), weight: .regular, align: .trailing, width: 54)
        }
        .font(.subheadline)
    }

    private func cell(
        _ text: String,
        weight: Font.Weight,
        align: Alignment,
        width: CGFloat,
        color: Color? = nil
    ) -> some View {
        Group {
            if width == .infinity {
                Text(text)
                    .fontWeight(weight)
                    .foregroundStyle(color ?? .primary)
                    .frame(maxWidth: .infinity, alignment: align)
            } else {
                Text(text)
                    .fontWeight(weight)
                    .foregroundStyle(color ?? .primary)
                    .frame(width: width, alignment: align)
            }
        }
    }

    private func tint(_ lb: Double) -> Color {
        if lb > 0.05 { return .red }
        if lb < -0.05 { return .green }
        return .primary
    }

    private func signedDelta(lb: Double) -> String {
        let v = weightUnit == .lbs ? lb : UnitConvert.lbToKg(lb)
        let prefix = v >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", v))"
    }

    private func percent(_ ratio: Double) -> String {
        String(format: "%.0f%%", ratio * 100.0)
    }
}
