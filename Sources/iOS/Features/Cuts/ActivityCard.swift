import SwiftUI
import SwiftData

extension Notification.Name {
    /// Posted when the user updates their daily step target via
    /// `StepTargetSheet`. Listeners (the activity card, the coach, etc.)
    /// observe this to refresh.
    static let activityTargetDidChange = Notification.Name("activityTargetDidChange")
}

/// One slot in the 7-day adherence strip. Carries enough context to drive
/// both the bar colour and the day-detail sheet.
private struct ActivityDaySlot: Identifiable {
    let id: Date
    let date: Date
    let activity: DailyActivity?
    let targetMet: Bool
}

/// Glance card shown on the Cuts tab. Renders the user's current step target
/// alongside today's progress and a 7-day adherence strip. The card is
/// global — it isn't scoped to a particular cut — so it doesn't take a
/// `cutStartDate` parameter.
///
/// Designed to live inside the Cuts-tab `NavigationStack` — does not
/// provide its own.
struct ActivityCard: View {
    @Environment(\.modelContext) private var modelContext

    @State private var stepTarget: Int = ScheduledNudgeStore.defaultStepTarget
    @State private var todaySteps: Int?
    @State private var lastSevenDays: [DailyActivity] = []
    @State private var showingTargetSheet: Bool = false
    @State private var selectedDaySlot: ActivityDaySlot? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            todayRow

            adherenceRow

            HStack {
                Spacer()
                Button("Edit target") {
                    showingTargetSheet = true
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding()
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .sheet(isPresented: $showingTargetSheet) {
            StepTargetSheet(currentTarget: stepTarget) { newTarget in
                UserDefaults.standard.set(newTarget, forKey: ScheduledNudgeStore.stepTargetKey)
                stepTarget = newTarget
                NotificationCenter.default.post(name: .activityTargetDidChange, object: nil)
            }
        }
        .sheet(item: $selectedDaySlot) { slot in
            DayActivitySheet(slot: slot, stepTarget: stepTarget)
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .mealScheduleDidChange)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .activityTargetDidChange)) { _ in
            reload()
        }
    }

    // MARK: - Header

    private var header: some View {
        Label("Activity", systemImage: "figure.walk")
            .font(.headline)
    }

    // MARK: - Today row

    @ViewBuilder
    private var todayRow: some View {
        if let todaySteps {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.numberFormatter.string(from: NSNumber(value: todaySteps)) ?? "\(todaySteps)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("/ \(Self.numberFormatter.string(from: NSNumber(value: stepTarget)) ?? "\(stepTarget)") steps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today: \(todaySteps) of \(stepTarget) steps")
        } else {
            Text("No data yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 7-day adherence row

    private var adherenceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sevenDayBars
            Text("7-day avg: \(Self.numberFormatter.string(from: NSNumber(value: sevenDayAverage)) ?? "\(sevenDayAverage)") steps")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Tap a bar for details")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var sevenDayBars: some View {
        // Always render seven slots so the strip width is stable even when
        // history is sparse. Missing days render as the dim "below target" colour.
        let slots = daySlots
        return HStack(spacing: 4) {
            ForEach(slots) { slot in
                Capsule()
                    .fill(slot.targetMet ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .frame(height: 18)
                    .accessibilityLabel(slot.targetMet ? "Target met" : "Below target")
                    .contentShape(Rectangle())
                    .onTapGesture { selectedDaySlot = slot }
            }
        }
    }

    // MARK: - Computed

    /// Seven oldest-to-newest day slots for the adherence strip.
    private var daySlots: [ActivityDaySlot] {
        let cal = Calendar.current
        let today = Reading.dayStart(of: Date())
        // idx 0 = 6 days ago, idx 6 = today
        let dayKeys: [Date] = (0..<7).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today)
        }
        let activityByDay: [Date: DailyActivity] = Dictionary(
            uniqueKeysWithValues: lastSevenDays.map { ($0.day, $0) }
        )
        return dayKeys.map { key in
            let activity = activityByDay[key]
            return ActivityDaySlot(
                id: key,
                date: key,
                activity: activity,
                targetMet: (activity?.steps ?? 0) >= stepTarget
            )
        }
    }

    private var sevenDayAverage: Int {
        guard !lastSevenDays.isEmpty else { return 0 }
        let sum = lastSevenDays.reduce(0) { $0 + $1.steps }
        return sum / lastSevenDays.count
    }

    // MARK: - Loading

    private func reload() {
        // Step target: pull from defaults, fall back to default if unset/zero.
        let stored = UserDefaults.standard.integer(forKey: ScheduledNudgeStore.stepTargetKey)
        stepTarget = stored > 0 ? stored : ScheduledNudgeStore.defaultStepTarget

        // Today's steps.
        let today = Reading.dayStart(of: Date())
        let todayPredicate = #Predicate<DailyActivity> { $0.day == today }
        var todayDescriptor = FetchDescriptor<DailyActivity>(predicate: todayPredicate)
        todayDescriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(todayDescriptor).first {
            todaySteps = record.steps
        } else {
            todaySteps = nil
        }

        // Last 7 days, most-recent first then trimmed to 7.
        let descriptor = FetchDescriptor<DailyActivity>(
            sortBy: [SortDescriptor(\.day, order: .reverse)]
        )
        let recent = (try? modelContext.fetch(descriptor)) ?? []
        lastSevenDays = Array(recent.prefix(7))
    }

    // MARK: - Formatters

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()
}

// MARK: - Day activity detail sheet

private struct DayActivitySheet: View {
    @Environment(\.dismiss) private var dismiss

    let slot: ActivityDaySlot
    let stepTarget: Int

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    private func fmt(_ n: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func fmt(_ d: Double) -> String {
        Self.numberFormatter.string(from: NSNumber(value: Int(d.rounded()))) ?? "\(Int(d.rounded()))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Steps") {
                    if let activity = slot.activity, activity.steps > 0 {
                        HStack {
                            Text("Steps")
                            Spacer()
                            Text(fmt(activity.steps))
                                .foregroundStyle(.primary)
                        }
                        HStack {
                            Text("Target")
                            Spacer()
                            Text(fmt(stepTarget))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Goal")
                            Spacer()
                            Label(
                                slot.targetMet ? "Met" : "Not met",
                                systemImage: slot.targetMet ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundStyle(slot.targetMet ? Color.accentColor : .secondary)
                            .labelStyle(.titleAndIcon)
                        }
                    } else {
                        Text("No step data for this day")
                            .foregroundStyle(.secondary)
                    }
                }

                let hasEnergy = slot.activity?.activeEnergyKcal != nil
                let hasExercise = slot.activity?.exerciseMinutes != nil
                if hasEnergy || hasExercise {
                    Section("Activity") {
                        if let kcal = slot.activity?.activeEnergyKcal {
                            HStack {
                                Text("Active Energy")
                                Spacer()
                                Text("\(fmt(kcal)) kcal")
                                    .foregroundStyle(.primary)
                            }
                        }
                        if let mins = slot.activity?.exerciseMinutes {
                            HStack {
                                Text("Exercise Time")
                                Spacer()
                                Text("\(mins) min")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Self.dateFormatter.string(from: slot.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Step target sheet

/// Modal presented when the user taps "Edit target" on `ActivityCard`.
/// Lets the user pick a daily step goal in 500-step increments. The new
/// value is persisted to `UserDefaults` and broadcast via
/// `Notification.Name.activityTargetDidChange`.
private struct StepTargetSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var currentTarget: Int
    let onSave: (Int) -> Void

    private static let minTarget = 2_000
    private static let maxTarget = 20_000
    private static let stepIncrement = 500

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 6) {
                    Text(Self.numberFormatter.string(from: NSNumber(value: currentTarget)) ?? "\(currentTarget)")
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("steps/day")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(currentTarget) steps per day")

                Stepper(
                    value: $currentTarget,
                    in: Self.minTarget...Self.maxTarget,
                    step: Self.stepIncrement
                ) {
                    Text("Daily step target")
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Step Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(currentTarget)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
