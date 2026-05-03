import SwiftUI

extension Notification.Name {
    /// Posted when the user taps the "Talk to coach" CTA on the empty
    /// meal-plan card. The Coach UI listens for this and opens with a
    /// pre-seeded "set up my meal plan" intent.
    static let openCoachForMealSetup = Notification.Name("openCoachForMealSetup")
}

/// Glance card shown on the Cuts tab. Reads the current `MealSchedulePeriod`
/// for the active cut and presents either:
///   • An empty state with two CTAs (coach / manual), OR
///   • A summary line + percent-split mini-bar that pushes
///     `MealPlanDetail` when tapped anywhere.
///
/// Designed to live inside the Cuts-tab `NavigationStack` — does not provide
/// its own.
struct MealPlanCard: View {
    @EnvironmentObject private var services: AppServices

    let cutStartDate: Date

    @State private var period: MealSchedulePeriod?
    @State private var slots: [MealSlot] = []
    @State private var dailyKcal: Int?
    @State private var planVersion: Int = 1
    @State private var manualSetupActive: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if period == nil || slots.isEmpty {
                emptyContent
            } else {
                NavigationLink {
                    MealPlanDetail(cutStartDate: cutStartDate)
                } label: {
                    summaryContent
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .navigationDestination(isPresented: $manualSetupActive) {
            MealPlanDetail(cutStartDate: cutStartDate, startInAddMode: true)
        }
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .mealScheduleDidChange)) { _ in
            reload()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Meal Plan", systemImage: "fork.knife")
                .font(.headline)
            Spacer()
            if period != nil, !slots.isEmpty {
                Text("Plan v\(planVersion)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: Capsule()
                    )
            }
        }
    }

    // MARK: - Empty state

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No meal plan yet. Your coach can build one, or set up manually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button {
                    NotificationCenter.default.post(name: .openCoachForMealSetup, object: nil)
                } label: {
                    Label("Talk to coach", systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: true)

                Button {
                    manualSetupActive = true
                } label: {
                    Label("Set up manually", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle()
            }
        }
    }

    // MARK: - Summary state

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(.primary)

            kcalSplitBar

            HStack {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meal plan, \(summaryLine), tap to view details")
    }

    /// Horizontal kcal split bar — one segment per slot, width proportional
    /// to that slot's share of the planned daily kcal. Slots with no
    /// inferable kcal contribute nothing.
    private var kcalSplitBar: some View {
        let segments = kcalSegments
        return GeometryReader { proxy in
            HStack(spacing: 2) {
                if segments.isEmpty {
                    Capsule()
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .frame(width: proxy.size.width, height: 8)
                } else {
                    ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                        Capsule()
                            .fill(seg.color)
                            .frame(width: max(2, proxy.size.width * seg.fraction), height: 8)
                            .accessibilityLabel("\(seg.name), \(Int(seg.fraction * 100)) percent")
                    }
                }
            }
        }
        .frame(height: 8)
    }

    // MARK: - Computed

    private var sortedSlots: [MealSlot] {
        slots.sorted { $0.minutesFromMidnight < $1.minutesFromMidnight }
    }

    private var summaryLine: String {
        let count = slots.count
        let mealsCopy = count == 1 ? "1 meal" : "\(count) meals"
        guard let first = sortedSlots.first, let last = sortedSlots.last else {
            return mealsCopy
        }
        let firstStr = MealAgendaPage.timeString(fromMinutesFromMidnight: first.minutesFromMidnight)
        let lastStr = MealAgendaPage.timeString(fromMinutesFromMidnight: last.minutesFromMidnight)
        if first.id == last.id {
            return "\(mealsCopy) · \(firstStr)"
        }
        return "\(mealsCopy) · \(firstStr)–\(lastStr)"
    }

    private struct Segment {
        let name: String
        let fraction: Double
        let color: Color
    }

    private var kcalSegments: [Segment] {
        // Build per-slot kcal contributions, then normalize to fractions of
        // the sum so the bar always fills regardless of whether the plan
        // adds up to the daily target.
        let sorted = sortedSlots
        var rawValues: [(String, Double)] = []
        for slot in sorted {
            let value: Double?
            if let kcal = slot.calculatedKcal {
                value = Double(kcal)
            } else if let pct = slot.kcalPercent, let daily = dailyKcal {
                value = Double(daily) * pct
            } else if let pct = slot.kcalPercent {
                // Even without a daily kcal target we can still draw a
                // proportional bar using the percentages directly.
                value = pct
            } else {
                value = nil
            }
            if let v = value, v > 0 {
                rawValues.append((slot.name, v))
            }
        }
        let total = rawValues.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        let palette: [Color] = [.orange, .pink, .purple, .blue, .teal, .green, .yellow]
        return rawValues.enumerated().map { idx, entry in
            Segment(
                name: entry.0,
                fraction: entry.1 / total,
                color: palette[idx % palette.count]
            )
        }
    }

    // MARK: - Loading

    private func reload() {
        let p = services.mealScheduleStore.currentPeriod(forCutStartDate: cutStartDate)
        period = p
        if let p {
            slots = services.mealScheduleStore.slots(forScheduleId: p.id)
            // Plan version is the count of all periods for this cut; the
            // current one is always the most recent, which we render as
            // "Plan vN" where N is the number of periods seen so far.
            planVersion = max(1, services.mealScheduleStore.periods(forCutStartDate: cutStartDate).count)
        } else {
            slots = []
            planVersion = 1
        }
        dailyKcal = services.macroPlanStore.currentPeriod(forCutStartDate: cutStartDate)?.kcal
    }
}
