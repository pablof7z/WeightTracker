import SwiftUI
import SwiftData

extension Notification.Name {
    /// Posted when the user taps the camera button next to a slot's food
    /// description. `userInfo["slotId"]` carries the slot's `UUID` so the
    /// photo-capture flow (handled elsewhere) knows which slot to attach to.
    static let openMealPhotoCapture = Notification.Name("openMealPhotoCapture")

    /// Posted when the user taps "Calculate" on a slot that has a food
    /// description but no calculated macros yet. `userInfo["slotId"]` carries
    /// the slot's `UUID`. The calculator integration is handled elsewhere.
    static let calculateMealForSlot = Notification.Name("calculateMealForSlot")
}

/// Editing surface for a single `MealSlot`. Used in two modes:
///   • `add`  — creates a brand-new slot in the cut's current meal schedule
///   • `edit` — mutates an existing slot in place (SwiftData reference type)
///
/// Saved either way via `try? context.save()` followed by a
/// `mealScheduleDidChange` notification so other views (Today agenda,
/// Cuts plan card) refresh.
struct MealSlotDetailView: View {
    enum Mode {
        case add
        case edit(MealSlot)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var services: AppServices

    let mode: Mode
    let cutStartDate: Date

    @State private var name: String = ""
    @State private var time: Date = Self.defaultTime()
    @State private var kcalPercent: Double = 0.25
    @State private var foodDescription: String = ""
    @State private var dailyKcal: Int = 2000
    @State private var calculatedSnapshot: CalculatedSnapshot?
    @State private var showToast: Bool = false
    @State private var slotIdForActions: UUID?

    private struct CalculatedSnapshot: Equatable {
        let kcal: Int
        let proteinG: Int
        let fatG: Int
        let carbsG: Int
        let at: Date
    }

    var body: some View {
        Form {
            Section("Meal") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                DatePicker(
                    "Time",
                    selection: $time,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.graphical)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Share of daily kcal")
                            .font(.subheadline)
                        Spacer()
                        Text(percentLabel)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $kcalPercent, in: 0.05...0.50, step: 0.05)
                }
            } header: {
                Text("Calories")
            } footer: {
                Text("Slider sets a planning target. Calculate macros from a food description below to override with ground-truth values.")
            }

            Section("Food") {
                HStack(alignment: .top, spacing: 8) {
                    TextField(
                        "e.g. 150g chicken + 200g rice",
                        text: $foodDescription,
                        axis: .vertical
                    )
                    .lineLimit(1...4)

                    Button {
                        postPhotoCapture()
                    } label: {
                        Image(systemName: "camera")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(minWidth: 44, minHeight: 44, alignment: .center)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add meal photo")
                }

                calculatedPanel
            }

            if case .edit = mode {
                Section {
                    Button(role: .destructive) {
                        deleteSlot()
                    } label: {
                        Label("Delete meal", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
            }
        }
        .overlay(alignment: .bottom) {
            if showToast {
                toastView
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task { loadInitialState() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var calculatedPanel: some View {
        if let snap = calculatedSnapshot {
            VStack(alignment: .leading, spacing: 6) {
                Text("Calculated")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(snap.kcal) kcal · \(snap.proteinG)g P · \(snap.fatG)g F · \(snap.carbsG)g C")
                    .font(.subheadline.monospacedDigit())
                Text("Calculated at \(Self.dateFormatter.string(from: snap.at))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 10)
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Macros not calculated — enter a food description first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    postCalculate()
                } label: {
                    Label("Calculate", systemImage: "sparkles")
                }
                .glassButtonStyle()
                .disabled(foodDescription.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
    }

    private var toastView: some View {
        Text("Plan updated")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassToastCapsule(tint: .accentColor)
    }

    // MARK: - Computed

    private var navTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        switch mode {
        case .add: return "New Meal"
        case .edit(let slot): return slot.name.isEmpty ? "New Meal" : slot.name
        }
    }

    private var estimatedKcal: Int {
        Int((Double(dailyKcal) * kcalPercent).rounded())
    }

    private var percentLabel: String {
        let pct = Int((kcalPercent * 100).rounded())
        return "\(pct)% · ~\(estimatedKcal) kcal"
    }

    private var minutesFromMidnight: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - Lifecycle

    private func loadInitialState() {
        // Pull the daily kcal target from the active macro plan period.
        if let period = services.macroPlanStore.currentPeriod(forCutStartDate: cutStartDate) {
            dailyKcal = period.kcal
        }

        switch mode {
        case .add:
            // Defaults already set by @State initializers.
            slotIdForActions = nil
        case .edit(let slot):
            name = slot.name
            time = Self.timeDate(forMinutes: slot.minutesFromMidnight)
            if let pct = slot.kcalPercent {
                kcalPercent = max(0.05, min(0.50, pct))
            }
            foodDescription = slot.foodDescription ?? ""
            slotIdForActions = slot.id
            if let kcal = slot.calculatedKcal,
               let p = slot.calculatedProteinG,
               let f = slot.calculatedFatG,
               let c = slot.calculatedCarbsG {
                calculatedSnapshot = CalculatedSnapshot(
                    kcal: kcal,
                    proteinG: p,
                    fatG: f,
                    carbsG: c,
                    at: slot.calculatedAt ?? Date()
                )
            }
        }
    }

    // MARK: - Save / delete

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedFood = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let foodValue: String? = trimmedFood.isEmpty ? nil : trimmedFood

        switch mode {
        case .add:
            guard let period = services.mealScheduleStore.currentPeriod(forCutStartDate: cutStartDate) else {
                // No active period yet — bail silently. The empty-state path on
                // the Cuts card handles initial setup; we should never reach
                // this branch from the standard flow.
                dismiss()
                return
            }
            let existing = services.mealScheduleStore.slots(forScheduleId: period.id)
            let nextSort = (existing.map(\.sortOrder).max() ?? 0) + 1000
            let newSlot = MealSlot(
                scheduleId: period.id,
                name: trimmedName,
                minutesFromMidnight: minutesFromMidnight,
                kind: .custom,
                sortOrder: nextSort,
                kcalPercent: kcalPercent,
                foodDescription: foodValue
            )
            context.insert(newSlot)
        case .edit(let slot):
            slot.name = trimmedName
            slot.minutesFromMidnight = minutesFromMidnight
            slot.sortOrder = minutesFromMidnight
            slot.kcalPercent = kcalPercent
            slot.foodDescription = foodValue
        }

        try? context.save()
        NotificationCenter.default.post(name: .mealScheduleDidChange, object: nil)

        showToastBriefly()
        // Slight delay so the toast registers before the view pops.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            dismiss()
        }
    }

    private func deleteSlot() {
        guard case .edit(let slot) = mode else { return }
        context.delete(slot)
        try? context.save()
        NotificationCenter.default.post(name: .mealScheduleDidChange, object: nil)
        dismiss()
    }

    private func showToastBriefly() {
        withAnimation(.easeOut(duration: 0.2)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeIn(duration: 0.2)) {
                showToast = false
            }
        }
    }

    // MARK: - Notifications

    private func postPhotoCapture() {
        let id = slotIdForActions ?? UUID()
        NotificationCenter.default.post(
            name: .openMealPhotoCapture,
            object: nil,
            userInfo: ["slotId": id]
        )
    }

    private func postCalculate() {
        guard let id = slotIdForActions else {
            // In add mode the slot doesn't exist yet — calculation is
            // post-save only.
            return
        }
        NotificationCenter.default.post(
            name: .calculateMealForSlot,
            object: nil,
            userInfo: ["slotId": id]
        )
    }

    // MARK: - Static helpers

    private static func defaultTime() -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func timeDate(forMinutes minutes: Int) -> Date {
        let h = max(0, min(23, minutes / 60))
        let m = max(0, min(59, minutes % 60))
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
