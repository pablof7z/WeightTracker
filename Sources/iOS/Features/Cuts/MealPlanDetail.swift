import SwiftUI

/// Full plan editor pushed onto the Cuts-tab `NavigationStack` from
/// `MealPlanCard`. Lists every `MealSlot` for the cut's current
/// `MealSchedulePeriod`, lets the user open one for editing, add a new
/// one, and surfaces a warning chip when the slot kcal sum drifts more
/// than 5% from the daily macro target.
struct MealPlanDetail: View {
    @EnvironmentObject private var services: AppServices

    let cutStartDate: Date
    /// When `true` the view auto-pushes a `MealSlotDetailView` in add mode
    /// the first time it appears. Used by the empty-state "Set up manually"
    /// button on `MealPlanCard`.
    var startInAddMode: Bool = false

    @State private var slots: [MealSlot] = []
    @State private var dailyKcal: Int?
    @State private var addSlotPresented: Bool = false
    @State private var didAutoOpenAdd: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if slots.isEmpty {
                    emptyState
                } else {
                    ForEach(sortedSlots) { slot in
                        NavigationLink {
                            MealSlotDetailView(mode: .edit(slot), cutStartDate: cutStartDate)
                        } label: {
                            MealSlotRow(slot: slot, dailyKcal: dailyKcal)
                        }
                        .buttonStyle(.plain)
                    }

                    totalsRow
                }
            }
            .padding()
        }
        .navigationTitle("Meal Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addSlotPresented = true
                } label: {
                    Label("Add meal", systemImage: "plus")
                }
            }
        }
        .navigationDestination(isPresented: $addSlotPresented) {
            MealSlotDetailView(mode: .add, cutStartDate: cutStartDate)
        }
        .task {
            reload()
            if startInAddMode, !didAutoOpenAdd {
                didAutoOpenAdd = true
                addSlotPresented = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mealScheduleDidChange)) { _ in
            reload()
        }
    }

    // MARK: - Sections

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No meals yet")
                .font(.headline)
            Text("Tap + to add your first meal slot.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var totalsRow: some View {
        let planTotal = totalKcal
        let target = dailyKcal
        let warning = warningCopy(planTotal: planTotal, target: target)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Plan total")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(planTotal.map { "\($0.formatted(.number.grouping(.automatic))) kcal" } ?? "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let warning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(warning)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color.orange.opacity(0.12),
                    in: Capsule()
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    // MARK: - Computed

    private var sortedSlots: [MealSlot] {
        slots.sorted { $0.minutesFromMidnight < $1.minutesFromMidnight }
    }

    /// Sum of slot kcal: prefer `calculatedKcal`, otherwise derive from
    /// `kcalPercent * dailyKcal` when both pieces are available. Returns nil
    /// when there are no slots that contribute to a meaningful total.
    private var totalKcal: Int? {
        guard !slots.isEmpty else { return nil }
        var sum = 0
        var contributed = false
        for slot in slots {
            if let kcal = slot.calculatedKcal {
                sum += kcal
                contributed = true
            } else if let pct = slot.kcalPercent, let daily = dailyKcal {
                sum += Int((Double(daily) * pct).rounded())
                contributed = true
            }
        }
        return contributed ? sum : nil
    }

    private func warningCopy(planTotal: Int?, target: Int?) -> String? {
        guard let planTotal, let target, target > 0 else { return nil }
        let delta = abs(Double(planTotal - target)) / Double(target)
        guard delta > 0.05 else { return nil }
        return "Plan total \(planTotal.formatted(.number.grouping(.automatic))) kcal · target \(target.formatted(.number.grouping(.automatic))) kcal"
    }

    // MARK: - Loading

    private func reload() {
        guard let period = services.mealScheduleStore.currentPeriod(forCutStartDate: cutStartDate) else {
            slots = []
            dailyKcal = services.macroPlanStore.currentPeriod(forCutStartDate: cutStartDate)?.kcal
            return
        }
        slots = services.mealScheduleStore.slots(forScheduleId: period.id)
        dailyKcal = services.macroPlanStore.currentPeriod(forCutStartDate: cutStartDate)?.kcal
    }
}

// MARK: - Row

/// One row in the plan list: time, name, food description (one line),
/// resolved kcal, and a chevron. Tapping pushes `MealSlotDetailView`.
struct MealSlotRow: View {
    let slot: MealSlot
    let dailyKcal: Int?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(timeString)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(slot.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                if let desc = slot.foodDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let kcal = resolvedKcal {
                    Text("\(kcal) kcal\(kcalSourceSuffix)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var timeString: String {
        MealAgendaPage.timeString(fromMinutesFromMidnight: slot.minutesFromMidnight)
    }

    private var resolvedKcal: Int? {
        if let cal = slot.calculatedKcal { return cal }
        guard let pct = slot.kcalPercent, let daily = dailyKcal else { return nil }
        return Int((Double(daily) * pct).rounded())
    }

    private var kcalSourceSuffix: String {
        slot.calculatedKcal != nil ? "" : " · planned"
    }

    private var accessibilityDescription: String {
        var parts: [String] = ["\(slot.name) at \(timeString)"]
        if let desc = slot.foodDescription, !desc.isEmpty {
            parts.append(desc)
        }
        if let kcal = resolvedKcal {
            parts.append("\(kcal) kilocalories")
        }
        return parts.joined(separator: ", ")
    }
}
