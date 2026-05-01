import SwiftUI

struct EditCutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue

    let original: ActiveCut
    var onSave: (ActiveCut) -> Void
    var onCancelCut: () -> Void

    @State private var startDate: Date
    @State private var startDisplayWeight: Double
    @State private var targetDisplayWeight: Double
    @State private var targetEndDate: Date
    @State private var reminderTime: Date

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }

    init(cut: ActiveCut, onSave: @escaping (ActiveCut) -> Void, onCancelCut: @escaping () -> Void) {
        self.original = cut
        self.onSave = onSave
        self.onCancelCut = onCancelCut

        let unitRaw = UserDefaults.standard.string(forKey: AppPrefKey.weightUnit) ?? WeightUnit.lbs.rawValue
        let unit = WeightUnit(rawValue: unitRaw) ?? .lbs
        _startDate = State(initialValue: cut.startDate)
        _startDisplayWeight = State(initialValue: UnitConvert.displayWeight(kg: cut.startWeightKg, in: unit))
        _targetDisplayWeight = State(initialValue: UnitConvert.displayWeight(kg: cut.targetWeightKg, in: unit))
        _targetEndDate = State(initialValue: cut.targetEndDate)

        let secs = cut.dailyReminderSecondsAfterMidnight
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = secs / 3600
        comps.minute = (secs % 3600) / 60
        _reminderTime = State(initialValue: Calendar.current.date(from: comps) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start") {
                    DatePicker(
                        "Started",
                        selection: $startDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    HStack {
                        Text("Starting weight")
                        Spacer()
                        TextField("Start", value: $startDisplayWeight, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(unit.symbol).foregroundStyle(.secondary)
                    }
                }

                Section("Target") {
                    HStack {
                        Text("Target weight")
                        Spacer()
                        TextField("Target", value: $targetDisplayWeight, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(unit.symbol).foregroundStyle(.secondary)
                    }
                    DatePicker("Target end date", selection: $targetEndDate, in: startDate..., displayedComponents: .date)
                }

                Section("Daily reminder") {
                    DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }

                Section {
                    Button(role: .destructive) {
                        onCancelCut()
                        dismiss()
                    } label: {
                        Label("End cut without saving as historical", systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle("Edit Cut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                        let seconds = (comps.hour ?? 7) * 3600 + (comps.minute ?? 30) * 60
                        let updated = ActiveCut(
                            startDate: Calendar.current.startOfDay(for: startDate),
                            startWeightKg: UnitConvert.storeWeight(startDisplayWeight, from: unit),
                            targetWeightKg: UnitConvert.storeWeight(targetDisplayWeight, from: unit),
                            targetEndDate: targetEndDate,
                            dailyReminderSecondsAfterMidnight: seconds
                        )
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(targetEndDate <= startDate)
                }
            }
        }
    }
}
