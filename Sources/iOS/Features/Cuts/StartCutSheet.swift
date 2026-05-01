import SwiftUI

struct StartCutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue

    let startWeightKg: Double
    var onStart: (ActiveCut) -> Void

    @State private var targetDisplayWeight: Double
    @State private var targetEndDate: Date
    @State private var reminderTime: Date

    init(startWeightKg: Double, onStart: @escaping (ActiveCut) -> Void) {
        self.startWeightKg = startWeightKg
        self.onStart = onStart

        // Default target: 158 lb (in stored unit, will be re-displayed appropriately).
        let defaultTargetKg = UnitConvert.lbToKg(AppConstants.defaultGoalLb)
        // We need the unit to format the default — but @AppStorage isn't available in init.
        // Read directly:
        let unitRaw = UserDefaults.standard.string(forKey: AppPrefKey.weightUnit) ?? WeightUnit.lbs.rawValue
        let unit = WeightUnit(rawValue: unitRaw) ?? .lbs
        _targetDisplayWeight = State(initialValue: UnitConvert.displayWeight(kg: defaultTargetKg, in: unit))

        let weeks = AppConstants.defaultCutDurationWeeks
        let endDate = Calendar.current.date(byAdding: .day, value: weeks * 7, to: Date()) ?? Date()
        _targetEndDate = State(initialValue: endDate)

        // Default reminder 7:30 am
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 7
        comps.minute = 30
        let reminder = Calendar.current.date(from: comps) ?? Date()
        _reminderTime = State(initialValue: reminder)
    }

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }
    private var startDisplayWeight: Double { UnitConvert.displayWeight(kg: startWeightKg, in: unit) }
    private var isValid: Bool { targetDisplayWeight > 0 && targetDisplayWeight < startDisplayWeight }

    private var ratePreview: String {
        guard isValid else { return "Target must be below your current weight" }
        let delta = startDisplayWeight - targetDisplayWeight
        let days = max(Calendar.current.dateComponents([.day], from: Date(), to: targetEndDate).day ?? 1, 1)
        let weeks = Double(days) / 7.0
        let perWeek = delta / max(weeks, 0.5)
        let durationStr = days < 14 ? "\(days) day\(days == 1 ? "" : "s")" : "\(Int(weeks.rounded())) weeks"
        return String(format: "%.1f %@/week over %@", perWeek, unit.symbol, durationStr)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Target weight")
                        Spacer()
                        TextField("Target", value: $targetDisplayWeight, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(unit.symbol).foregroundStyle(.secondary)
                    }
                    DatePicker("Target end date", selection: $targetEndDate, in: Date()..., displayedComponents: .date)
                } header: {
                    Text("Target")
                } footer: {
                    Text(ratePreview)
                        .foregroundStyle(isValid ? Color.secondary : Color.red)
                }

                Section("Daily reminder") {
                    DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }

                Section {
                    HStack {
                        Text("Starting weight")
                        Spacer()
                        Text(formatStart())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Start Cut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let targetKg = UnitConvert.storeWeight(targetDisplayWeight, from: unit)
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                        let seconds = (comps.hour ?? 7) * 3600 + (comps.minute ?? 30) * 60
                        let cut = ActiveCut(
                            startDate: Date(),
                            startWeightKg: startWeightKg,
                            targetWeightKg: targetKg,
                            targetEndDate: targetEndDate,
                            dailyReminderSecondsAfterMidnight: seconds
                        )
                        onStart(cut)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func formatStart() -> String {
        let v = UnitConvert.displayWeight(kg: startWeightKg, in: unit)
        return String(format: "%.1f %@", v, unit.symbol)
    }
}
