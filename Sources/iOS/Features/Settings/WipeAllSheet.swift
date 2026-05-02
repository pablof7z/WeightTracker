import SwiftUI

struct WipeAllSheet: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue

    @State private var typedConfirmation: String = ""
    @State private var didWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This will permanently delete every reading. This cannot be undone.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if let prompt = confirmationPrompt {
                    Section("Confirm") {
                        Text("To confirm, type your most recent weight: \(prompt)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("Weight", text: $typedConfirmation)
                            .keyboardType(.decimalPad)
                    }
                    Section {
                        Button(role: .destructive) {
                            performWipe()
                        } label: {
                            Text("Wipe all data")
                                .frame(maxWidth: .infinity)
                        }
                        .glassButtonStyle(prominent: true)
                        .tint(.red)
                        .disabled(!matches(prompt))
                    }
                } else {
                    Section {
                        Text("There are no readings to wipe.")
                            .foregroundStyle(.secondary)
                    }
                }
                if didWipe {
                    Section { Label("All readings deleted.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Wipe all data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didWipe ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }

    private var mostRecentDisplay: Double? {
        guard let r = appServices.repository.mostRecent() else { return nil }
        return UnitConvert.displayWeight(kg: r.weightKg, in: weightUnit).rounded(toPlaces: 1)
    }

    private var confirmationPrompt: String? {
        guard let v = mostRecentDisplay else { return nil }
        return "\(formatted(v)) \(weightUnit.symbol)"
    }

    private func matches(_ prompt: String) -> Bool {
        guard let target = mostRecentDisplay else { return false }
        let cleaned = typedConfirmation
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let typed = Double(cleaned) else { return false }
        return abs(typed - target) < 0.05
    }

    private func formatted(_ v: Double) -> String {
        String(format: "%.1f", v)
    }

    private func performWipe() {
        appServices.repository.deleteAll()
        ActiveCutStore.save(nil)
        didWipe = true
        Task { await appServices.notifications.scheduleEvaluatedTriggers() }
    }
}
