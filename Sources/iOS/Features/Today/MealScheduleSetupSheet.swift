import SwiftUI

struct MealScheduleSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var services: AppServices

    @State private var draftSlots: [DraftSlot] = []
    @State private var originalSnapshot: [DraftSnapshot] = []
    @State private var isSaving = false

    struct DraftSlot: Identifiable {
        let id = UUID()
        var name: String
        var time: Date  // only time component matters
        var kind: MealKind
    }

    /// Lightweight value type used to detect dirty state across edits.
    private struct DraftSnapshot: Equatable {
        var name: String
        var minutes: Int
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($draftSlots) { $slot in
                        HStack(spacing: 12) {
                            TextField("Meal name", text: $slot.name)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                            Spacer(minLength: 8)
                            DatePicker(
                                "Time",
                                selection: $slot.time,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        }
                    }
                    .onDelete { indices in
                        draftSlots.remove(atOffsets: indices)
                    }

                    Button {
                        appendDefaultMeal()
                    } label: {
                        Label("Add meal", systemImage: "plus")
                    }
                } header: {
                    Text("Meals")
                } footer: {
                    Text("List the meals you eat each day and when. The coach uses this to look at your timing patterns.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Meal Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saveDisabled)
                        .fontWeight(isDirty ? .semibold : .regular)
                }
            }
            .task { loadCurrentSchedule() }
        }
        // Adapt to medium height when keyboard not up; large when typing room is needed.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Dirty / save state

    private var currentSnapshot: [DraftSnapshot] {
        let cal = Calendar.current
        return draftSlots.map { slot in
            let comps = cal.dateComponents([.hour, .minute], from: slot.time)
            let mins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            return DraftSnapshot(
                name: slot.name.trimmingCharacters(in: .whitespaces),
                minutes: mins
            )
        }
    }

    private var isDirty: Bool {
        currentSnapshot != originalSnapshot
    }

    private var saveDisabled: Bool {
        if isSaving { return true }
        if draftSlots.allSatisfy({ $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return true
        }
        return !isDirty
    }

    // MARK: - Mutations

    private func appendDefaultMeal() {
        // Suggest a time roughly 4 hours after the last meal, or noon if empty.
        let cal = Calendar.current
        let suggested: Date = {
            if let last = draftSlots.last {
                return cal.date(byAdding: .hour, value: 4, to: last.time) ?? last.time
            }
            return cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        }()
        withAnimation(.easeInOut(duration: 0.18)) {
            draftSlots.append(DraftSlot(name: "", time: suggested, kind: .custom))
        }
    }

    // MARK: - Load / save

    private func loadCurrentSchedule() {
        guard let cut = ActiveCutStore.load() else {
            draftSlots = MealScheduleSetupSheet.defaultDraftSlots()
            originalSnapshot = currentSnapshot
            return
        }
        guard let period = services.mealScheduleStore.currentPeriod(forCutStartDate: cut.startDate) else {
            draftSlots = MealScheduleSetupSheet.defaultDraftSlots()
            originalSnapshot = currentSnapshot
            return
        }
        let slots = services.mealScheduleStore.slots(forScheduleId: period.id)
        let calendar = Calendar.current
        draftSlots = slots.map { slot in
            let h = slot.minutesFromMidnight / 60
            let m = slot.minutesFromMidnight % 60
            let t = calendar.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
            return DraftSlot(name: slot.name, time: t, kind: slot.kind)
        }
        originalSnapshot = currentSnapshot
    }

    private static func defaultDraftSlots() -> [DraftSlot] {
        let calendar = Calendar.current
        let defaults: [(String, Int, Int, MealKind)] = [
            ("Breakfast", 8, 0, .breakfast),
            ("Lunch", 12, 30, .lunch),
            ("Dinner", 19, 0, .dinner),
        ]
        return defaults.map { (name, h, m, kind) in
            let t = calendar.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
            return DraftSlot(name: name, time: t, kind: kind)
        }
    }

    private func save() {
        guard let cut = ActiveCutStore.load() else { return }
        isSaving = true
        let calendar = Calendar.current
        let inputs = draftSlots
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { a, b in
                let ca = calendar.dateComponents([.hour, .minute], from: a.time)
                let cb = calendar.dateComponents([.hour, .minute], from: b.time)
                let ma = (ca.hour ?? 0) * 60 + (ca.minute ?? 0)
                let mb = (cb.hour ?? 0) * 60 + (cb.minute ?? 0)
                return ma < mb
            }
            .enumerated()
            .map { (idx, slot) -> MealSlotInput in
                let comps = calendar.dateComponents([.hour, .minute], from: slot.time)
                let mins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                return MealSlotInput(
                    name: slot.name.trimmingCharacters(in: .whitespaces),
                    minutesFromMidnight: mins,
                    kind: slot.kind,
                    sortOrder: idx
                )
            }
        do {
            if services.mealScheduleStore.currentPeriod(forCutStartDate: cut.startDate) != nil {
                try services.mealScheduleStore.replaceCurrentPeriod(
                    cutStartDate: cut.startDate,
                    slotInputs: inputs,
                    note: nil,
                    now: Date()
                )
            } else {
                try services.mealScheduleStore.insertInitialPeriod(
                    cutStartDate: cut.startDate,
                    startDate: Date(),
                    slotInputs: inputs,
                    note: nil
                )
            }
            dismiss()
        } catch {
            // No alert UI in this minimal setup sheet; just dismiss.
            dismiss()
        }
    }
}
