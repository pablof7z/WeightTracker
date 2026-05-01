import SwiftUI

struct GapDetailSheet: View {
    let gap: Gap
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue

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
        NavigationStack {
            List {
                Section("Gap") {
                    row("Start", value: Self.dateFormatter.string(from: gap.startDate))
                    row("End", value: Self.dateFormatter.string(from: gap.endDate))
                    row("Duration", value: "\(gap.durationDays) day\(gap.durationDays == 1 ? "" : "s")")
                }
                Section("Weights") {
                    row("Start", value: weightString(kg: gap.weightStartKg))
                    row("End", value: weightString(kg: gap.weightEndKg))
                }
                Section("Drift") {
                    row("Total", value: signedDelta(lb: gap.driftLb))
                        .foregroundStyle(gap.didGain ? .red : .green)
                    row("Per month", value: signedDelta(lb: gap.driftLbPerMonth))
                    row("Direction", value: gap.didGain ? "Gain" : "Loss")
                }
            }
            .navigationTitle("Gap details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func weightString(kg: Double) -> String {
        let v = UnitConvert.displayWeight(kg: kg, in: weightUnit)
        return String(format: "%.1f %@", v, weightUnit.symbol)
    }

    private func signedDelta(lb: Double) -> String {
        let v = weightUnit == .lbs ? lb : UnitConvert.lbToKg(lb)
        let prefix = v >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", v)) \(weightUnit.symbol)"
    }
}
