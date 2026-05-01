import SwiftUI

struct EditCutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue

    let original: ActiveCut
    var onSave: (ActiveCut) -> Void
    var onCancelCut: () -> Void

    @State private var startDate: Date
    @State private var startDisplayWeight: Double
    @State private var targetDisplayWeight: Double
    @State private var targetEndDate: Date
    @State private var reminderTime: Date

    @State private var showReviewMacrosSheet = false
    @State private var showConfirmEnd = false

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }

    private var isValid: Bool {
        targetEndDate > startDate
            && targetDisplayWeight > 0
            && startDisplayWeight > 0
            && targetDisplayWeight < startDisplayWeight
    }

    private var validationMessage: String? {
        if targetDisplayWeight >= startDisplayWeight {
            return "Target must be lower than starting weight."
        }
        if targetEndDate <= startDate {
            return "Target date must be after the start."
        }
        return nil
    }

    /// Has the user nudged the target weight away from the original cut's
    /// target? If so, we show a non-blocking banner offering to review macros.
    private var targetChanged: Bool {
        let originalDisplay = UnitConvert.displayWeight(kg: original.targetWeightKg, in: unit)
        return abs(targetDisplayWeight - originalDisplay) >= 0.05
    }

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
                    DatePicker("Target end date", selection: $targetEndDate, in: startDate..., displayedComponents: .date)
                } header: {
                    Text("Target")
                } footer: {
                    if let msg = validationMessage {
                        Text(msg).foregroundStyle(Color.red)
                    }
                }

                if targetChanged {
                    Section {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text(MacroCopy.editCutTargetChangedBanner)
                                .font(.subheadline)
                            Spacer()
                            Button(MacroCopy.editCutOpen) {
                                showReviewMacrosSheet = true
                            }
                            .font(.subheadline.weight(.medium))
                        }
                    }
                }

                Section {
                    DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Daily reminder")
                } footer: {
                    Text("We'll send a gentle nudge to weigh in at this time each day.")
                }

                Section {
                    Button(role: .destructive) {
                        showConfirmEnd = true
                    } label: {
                        Label("End Cut", systemImage: "xmark.circle")
                    }
                    .confirmationDialog(
                        "End this cut?",
                        isPresented: $showConfirmEnd,
                        titleVisibility: .visible
                    ) {
                        Button("End Cut", role: .destructive) {
                            onCancelCut()
                            dismiss()
                        }
                    } message: {
                        Text("The cut won't be saved to history.")
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
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showReviewMacrosSheet) {
                let cutStart = Reading.dayStart(of: original.startDate)
                let current = services.macroPlanStore.currentPeriod(forCutStartDate: cutStart)
                let initial: (Int, Int, Int, Int) = current.map {
                    ($0.kcal, $0.proteinG ?? 0, $0.fatG ?? 0, $0.carbsG ?? 0)
                } ?? (2000, 150, 60, 200)
                let defaults = currentDefaultsTuple()
                EditMacrosSheet(
                    cutStartDate: cutStart,
                    initial: initial,
                    defaults: defaults
                ) { kcal, p, f, c in
                    services.macroPlanStore.replaceCurrentPeriod(
                        cutStartDate: cutStart,
                        kcal: kcal,
                        proteinG: p,
                        fatG: f,
                        carbsG: c
                    )
                    services.cutCoach.refresh(trigger: .macroPlanChanged)
                }
                .environmentObject(services)
            }
        }
    }

    private func currentDefaultsTuple() -> (kcal: Int, proteinG: Int, fatG: Int, carbsG: Int) {
        let sex = Sex(rawValue: UserDefaults.standard.string(forKey: AppPrefKey.userSex) ?? MacroDefaultsPrefs.sex)
            ?? .male
        let age = (UserDefaults.standard.object(forKey: AppPrefKey.userAgeYears) as? Int) ?? MacroDefaultsPrefs.ageYears
        let height = (UserDefaults.standard.object(forKey: AppPrefKey.userHeightCm) as? Double) ?? MacroDefaultsPrefs.heightCm
        let activity = (UserDefaults.standard.object(forKey: AppPrefKey.userActivityFactor) as? Double)
            ?? MacroDefaultsPrefs.activityFactor

        return MacroDefaults.compute(
            startWeightKg: original.startWeightKg,
            targetWeightKg: UnitConvert.storeWeight(targetDisplayWeight, from: unit),
            startDate: original.startDate,
            targetEndDate: targetEndDate,
            sex: sex,
            ageYears: age,
            heightCm: height,
            activityFactor: activity
        )
    }
}
