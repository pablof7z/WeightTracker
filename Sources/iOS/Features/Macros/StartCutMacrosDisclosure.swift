import SwiftUI

/// Collapsed-by-default disclosure embedded in `StartCutSheet`. When closed it
/// shows a single-line summary of the proposed defaults; when expanded it
/// reveals editable macro controls plus a Reset link. Skipping = leaving it
/// collapsed; the bound values still travel to `StartCutSheet`'s save.
struct StartCutMacrosDisclosure: View {
    @Binding var proteinG: Int
    @Binding var fatG: Int
    @Binding var carbsG: Int
    let defaults: (kcal: Int, proteinG: Int, fatG: Int, carbsG: Int)

    @State private var expanded: Bool = false

    private var computedKcal: Int {
        MacroDefaults.totalKcal(proteinG: proteinG, fatG: fatG, carbsG: carbsG)
    }

    private var summary: String {
        "\(computedKcal.formatted()) kcal · \(proteinG)/\(fatG)/\(carbsG)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MacroCopy.startCutDisclosureLabel)
                            .font(.subheadline.weight(.medium))
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            if expanded {
                VStack(spacing: 8) {
                    calorieRow
                    stepperRow(label: MacroCopy.editProtein, value: $proteinG, step: 5, min: 0, max: 500, suffix: MacroCopy.editGramSuffix)
                    stepperRow(label: MacroCopy.editFat, value: $fatG, step: 5, min: 0, max: 300, suffix: MacroCopy.editGramSuffix)
                    stepperRow(label: MacroCopy.editCarbs, value: $carbsG, step: 5, min: 0, max: 800, suffix: MacroCopy.editGramSuffix)
                    HStack {
                        Spacer()
                        Button(MacroCopy.editReset) {
                            proteinG = defaults.proteinG
                            fatG = defaults.fatG
                            carbsG = defaults.carbsG
                        }
                        .font(.footnote)
                    }

                    Text(MacroCopy.startCutDisclosureHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var calorieRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(MacroCopy.editCalories)
                .font(.subheadline)
            Spacer()
            Text(computedKcal.formatted())
                .font(.subheadline.monospacedDigit())
            Text(MacroCopy.editKcal)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stepperRow(
        label: String,
        value: Binding<Int>,
        step: Int,
        min: Int,
        max: Int,
        suffix: String
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 10) {
                Button {
                    let newVal = Swift.max(min, value.wrappedValue - step)
                    if newVal != value.wrappedValue {
                        value.wrappedValue = newVal
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                MacroNumberField(
                    value: value,
                    min: min,
                    max: max,
                    suffix: suffix,
                    font: .subheadline.monospacedDigit(),
                    fieldWidth: 52
                )

                Button {
                    let newVal = Swift.min(max, value.wrappedValue + step)
                    if newVal != value.wrappedValue {
                        value.wrappedValue = newVal
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
