import SwiftUI

struct MealAgendaPage: View {
    @EnvironmentObject var services: AppServices

    @State private var schedule: MealSchedulePeriod?
    @State private var slots: [MealSlot] = []
    @State private var todayEvents: [MealEvent] = []
    @State private var setupSheetPresented = false
    @State private var lastLoggedSlotID: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let nowMinutes = Calendar.current.minutesFromMidnightHelper(context.date)
            content(nowMinutes: nowMinutes, now: context.date)
        }
        .sheet(isPresented: $setupSheetPresented, onDismiss: { reload() }) {
            MealScheduleSetupSheet()
                .environmentObject(services)
        }
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .mealScheduleDidChange)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .mealEventDidChange)) { _ in reloadEvents() }
        .sensoryFeedback(.success, trigger: lastLoggedSlotID)
    }

    @ViewBuilder
    private func content(nowMinutes: Int, now: Date) -> some View {
        if slots.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(timelineRows(nowMinutes: nowMinutes, now: now)) { row in
                        switch row.kind {
                        case .now(let date):
                            nowLine(now: date)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                                .transition(.opacity)
                        case .slot(let slot, let isPast):
                            MealSlotCard(
                                slot: slot,
                                event: event(for: slot),
                                isPast: isPast,
                                activePeriod: activeMacroPeriod(),
                                onLog: { logMeal(slot: slot, status: .eaten) },
                                onSkip: { logMeal(slot: slot, status: .skipped) }
                            )
                            .padding(.horizontal)
                        }
                    }

                    if let schedule, !slots.isEmpty {
                        Button {
                            setupSheetPresented = true
                        } label: {
                            Label("Edit schedule", systemImage: "slider.horizontal.3")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                        .accessibilityLabel("Edit meal schedule")
                        .id(schedule.id) // re-render if schedule swaps
                    }
                }
                .padding(.top, 56)         // clear the parent toolbar / status zone
                .padding(.bottom, 48)      // clear the home indicator
                .animation(.easeInOut(duration: 0.25), value: slots.map(\.id))
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Timeline rows

    private struct TimelineRow: Identifiable {
        let id: AnyHashable
        let kind: Kind
        enum Kind {
            case slot(MealSlot, isPast: Bool)
            case now(Date)
        }
    }

    /// Builds the unified, sorted list of rows for the timeline. The "now" row is
    /// inserted at the correct position relative to the slots — handling these
    /// edge cases naturally:
    ///   • All slots in the past   → now-line goes at the bottom
    ///   • All slots in the future → now-line goes at the top
    ///   • Mixed                   → now-line is interleaved at the boundary
    private func timelineRows(nowMinutes: Int, now: Date) -> [TimelineRow] {
        let sorted = slots.sorted { $0.minutesFromMidnight < $1.minutesFromMidnight }
        var rows: [TimelineRow] = []
        var nowInserted = false
        for slot in sorted {
            if !nowInserted, slot.minutesFromMidnight > nowMinutes {
                rows.append(TimelineRow(id: "now", kind: .now(now)))
                nowInserted = true
            }
            let isPast = slot.minutesFromMidnight <= nowMinutes
            rows.append(TimelineRow(id: slot.id, kind: .slot(slot, isPast: isPast)))
        }
        if !nowInserted {
            rows.append(TimelineRow(id: "now", kind: .now(now)))
        }
        return rows
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.18), Color.pink.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: "fork.knife")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 6) {
                Text("Plan your meals")
                    .font(.title3.weight(.semibold))
                Text("Tell the app when you usually eat. We’ll keep the day on track and the coach will look for patterns.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                setupSheetPresented = true
            } label: {
                Label("Set up meals", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 8)
            }
            .glassButtonStyle(prominent: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 48)
    }

    // MARK: - Now line

    private func nowLine(now: Date) -> some View {
        HStack(spacing: 8) {
            Text(Self.timeFormatter.string(from: now))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.red.opacity(0.12), in: Capsule())
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.red, .red.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current time \(Self.timeFormatter.string(from: now))")
    }

    // MARK: - Helpers

    private func event(for slot: MealSlot) -> MealEvent? {
        todayEvents.first { $0.slotId == slot.id }
    }

    private func activeMacroPeriod() -> MacroPlanPeriod? {
        guard let cut = ActiveCutStore.load() else { return nil }
        return services.macroPlanStore.currentPeriod(forCutStartDate: cut.startDate)
    }

    private func logMeal(slot: MealSlot, status: MealEventStatus) {
        let cal = Calendar.current
        let h = slot.minutesFromMidnight / 60
        let m = slot.minutesFromMidnight % 60
        let scheduledAt = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
        let ateAt = (status == .eaten) ? Date() : scheduledAt
        _ = services.mealEventStore.upsert(
            slotId: slot.id,
            slotNameSnapshot: slot.name,
            scheduleId: schedule?.id,
            ateAt: ateAt,
            status: status,
            hungerBefore: nil,
            hungerAfter: nil,
            note: nil,
            now: Date()
        )
        if status == .eaten {
            // Triggers the .sensoryFeedback(.success) on this view.
            lastLoggedSlotID = slot.id
        }
        reloadEvents()
    }

    private func reload() {
        guard let cut = ActiveCutStore.load() else {
            schedule = nil
            slots = []
            todayEvents = []
            return
        }
        schedule = services.mealScheduleStore.currentPeriod(forCutStartDate: cut.startDate)
        if let s = schedule {
            slots = services.mealScheduleStore.slots(forScheduleId: s.id)
        } else {
            slots = []
        }
        reloadEvents()
    }

    private func reloadEvents() {
        todayEvents = services.mealEventStore.events(on: Date())
    }

    // MARK: - Formatting

    /// Locale-aware short time formatter (respects the user's 12/24h preference).
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    /// Convert minutes-from-midnight to a `Date` anchored on today, then format.
    static func timeString(fromMinutesFromMidnight minutes: Int) -> String {
        let cal = Calendar.current
        let h = max(0, min(23, minutes / 60))
        let m = max(0, min(59, minutes % 60))
        let date = cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
        return timeFormatter.string(from: date)
    }
}

private extension Calendar {
    func minutesFromMidnightHelper(_ date: Date) -> Int {
        let comps = dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

// MARK: - Meal slot card

private struct MealSlotCard: View {
    let slot: MealSlot
    let event: MealEvent?
    let isPast: Bool
    let activePeriod: MacroPlanPeriod?
    let onLog: () -> Void
    let onSkip: () -> Void

    private var isLogged: Bool { event?.status == .eaten || event?.status == .partial }
    private var isSkipped: Bool { event?.status == .skipped }
    private var isMissed: Bool { isPast && !isLogged && !isSkipped }

    var body: some View {
        HStack(spacing: 12) {
            stateAccent
                .frame(width: 4)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(timeString)
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(timeColor)
                Text(slot.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(nameColor)
                    .strikethrough(isSkipped, color: .secondary)
                if let desc = slot.foodDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let kcal = resolvedKcal {
                    let proteinStr = resolvedProtein.map { " · \($0)g P" } ?? ""
                    Text("\(kcal) kcal\(proteinStr)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            trailingControl
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(stateBackground, in: RoundedRectangle(cornerRadius: 14))
        .glass(in: RoundedRectangle(cornerRadius: 14))
        .opacity(isSkipped ? 0.55 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSkipped {
                Button(role: .destructive, action: onSkip) {
                    Label("Skip", systemImage: "xmark.circle")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: State styling

    private var stateAccent: some View {
        Group {
            if isLogged {
                Color.green
            } else if isSkipped {
                Color.gray.opacity(0.4)
            } else if isMissed {
                Color.orange
            } else {
                Color.accentColor.opacity(0.55)
            }
        }
    }

    private var stateBackground: Color {
        if isLogged { return Color.green.opacity(0.08) }
        if isMissed { return Color.orange.opacity(0.06) }
        return Color.clear
    }

    private var nameColor: Color {
        if isSkipped { return .secondary }
        return .primary
    }

    private var timeColor: Color {
        if isMissed { return .orange }
        return .secondary
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isLogged {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
                .accessibilityHidden(true)
        } else if isSkipped {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.title2)
                .accessibilityHidden(true)
        } else {
            Button(action: onLog) {
                Image(systemName: isMissed ? "exclamationmark.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(isMissed ? Color.orange : Color.secondary)
                    .contentShape(Rectangle())
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log \(slot.name) as eaten")
        }
    }

    private var timeString: String {
        MealAgendaPage.timeString(fromMinutesFromMidnight: slot.minutesFromMidnight)
    }

    private var resolvedKcal: Int? {
        // Calculated absolute values take priority — they reflect the actual
        // food planned for this slot, not the daily-target percentage.
        if let cal = slot.calculatedKcal { return cal }
        guard let pct = slot.kcalPercent, let period = activePeriod else { return nil }
        return Int(Double(period.kcal) * pct)
    }

    private var resolvedProtein: Int? {
        if let cal = slot.calculatedProteinG { return cal }
        guard let pct = slot.proteinPercent, let proteinG = activePeriod?.proteinG else { return nil }
        return Int(Double(proteinG) * pct)
    }

    private var accessibilityDescription: String {
        let state: String
        if isLogged { state = "logged" }
        else if isSkipped { state = "skipped" }
        else if isMissed { state = "missed, not yet logged" }
        else { state = "upcoming" }
        return "\(slot.name) at \(timeString), \(state)"
    }
}
