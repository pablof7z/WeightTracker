import SwiftUI

/// Quiet projected-weight indicator on Today. Rotates through four horizons
/// across the day — opening the app in the morning shows a different horizon
/// than opening it in the evening. Tap to cycle manually.
///
/// Display rules (see `/tmp/projected-weight-*-brainstorm.md`):
///   - Bare type, no card. Matches the deficit widget's restraint.
///   - Single line: `≈ 172.1 lb in 30 days`.
///   - Caption: lower–upper band + goal anchor.
///   - Tap → cycle to the next horizon (wraps). NO auto-cycle while visible.
///   - Stale data (>3 days): suffix " · stale" in tertiary color.
///   - Flat trend (|r| < 0.01 lb/day): "no change projected".
///   - Adaptive copy is "lite" per spec — no celebration, no loss framing.
///
/// Milestone horizons (e.g. "Trip · May 25") plug into the rotation when the
/// user has scheduled any: hour bucket 12–17 (which would normally show 90d)
/// renders the nearest upcoming milestone instead. Multiple milestones cycle
/// with `dayOfYear % count`. Tap-cycle order becomes
/// `[7d, 30d, milestones..., goalDate]`.
struct WeightForecastWidget: View {

    let readings: [Reading]
    let activeCut: ActiveCut
    let weightUnit: WeightUnit
    let milestones: [Milestone]

    @State private var horizonOverride: Horizon?

    init(
        readings: [Reading],
        activeCut: ActiveCut,
        weightUnit: WeightUnit,
        milestones: [Milestone] = []
    ) {
        self.readings = readings
        self.activeCut = activeCut
        self.weightUnit = weightUnit
        self.milestones = milestones
    }

    /// Horizon variants. Tap order is fixed
    /// `7d → 30d → milestones... → goalDate → 7d`. When the user has at
    /// least one milestone the 90d slot is dropped (per spec); otherwise
    /// it slots in between 30d and goalDate.
    enum Horizon: Hashable {
        case sevenDay
        case thirtyDay
        case ninetyDay
        case milestone(Milestone)
        case cutGoalDate

        /// Default horizon for the user's local hour. Four-hour-buckets, same
        /// rotation idea as before. When the user has any milestones the
        /// 12–17 bucket maps to the nearest one (rotated by day-of-year when
        /// multiple exist) instead of 90d.
        static func defaultForHour(_ hour: Int, milestones: [Milestone], calendar: Calendar = .current, today: Date = Date()) -> Horizon {
            switch hour {
            case 0...5: return .sevenDay
            case 6...11: return .thirtyDay
            case 12...17:
                if let m = pickMilestone(milestones: milestones, calendar: calendar, today: today) {
                    return .milestone(m)
                }
                return .ninetyDay
            default: return .cutGoalDate
            }
        }

        /// Deterministic milestone pick: nearest upcoming, but when multiple
        /// exist rotate through them by `dayOfYear % count` so the user sees
        /// a different one each day without animation.
        static func pickMilestone(milestones: [Milestone], calendar: Calendar = .current, today: Date = Date()) -> Milestone? {
            guard !milestones.isEmpty else { return nil }
            let dayStart = calendar.startOfDay(for: today)
            let upcoming = milestones
                .filter { $0.date >= dayStart }
                .sorted { $0.date < $1.date }
            guard !upcoming.isEmpty else { return nil }
            if upcoming.count == 1 { return upcoming[0] }
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: dayStart) ?? 0
            let idx = ((dayOfYear % upcoming.count) + upcoming.count) % upcoming.count
            return upcoming[idx]
        }

        /// Days from `asOf` to the projected date.
        func horizonDays(activeCut: ActiveCut, asOf: Date, calendar: Calendar) -> Int {
            switch self {
            case .sevenDay: return 7
            case .thirtyDay: return 30
            case .ninetyDay: return 90
            case .milestone(let m):
                let today = calendar.startOfDay(for: asOf)
                let target = calendar.startOfDay(for: m.date)
                return max(1, calendar.dateComponents([.day], from: today, to: target).day ?? 1)
            case .cutGoalDate:
                let today = calendar.startOfDay(for: asOf)
                let end = calendar.startOfDay(for: activeCut.targetEndDate)
                return max(1, calendar.dateComponents([.day], from: today, to: end).day ?? 1)
            }
        }
    }

    // MARK: - Rotation

    /// Build the tap-cycle order for the current widget state. When any
    /// milestones exist the 90d slot is dropped (per spec).
    private var rotation: [Horizon] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let upcoming = milestones
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
        var ordered: [Horizon] = [.sevenDay, .thirtyDay]
        if upcoming.isEmpty {
            ordered.append(.ninetyDay)
        } else {
            ordered.append(contentsOf: upcoming.map(Horizon.milestone))
        }
        ordered.append(.cutGoalDate)
        return ordered
    }

    private func nextHorizon(after current: Horizon) -> Horizon {
        let all = rotation
        guard !all.isEmpty else { return current }
        if let idx = all.firstIndex(of: current) {
            return all[(idx + 1) % all.count]
        }
        // Override was set to a horizon that's no longer in the rotation
        // (e.g. the milestone was deleted). Fall back to the first.
        return all[0]
    }

    // MARK: - Date formatters

    private static let monthDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let monthDayYearFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private func milestoneDateString(_ date: Date) -> String {
        let cal = Calendar.current
        let nowYear = cal.component(.year, from: Date())
        let dateYear = cal.component(.year, from: date)
        return dateYear == nowYear
            ? Self.monthDayFmt.string(from: date)
            : Self.monthDayYearFmt.string(from: date)
    }

    /// "today" / "tomorrow" / "in N days" with correct pluralization. Used
    /// only by the milestone caption.
    private func relativeDayPhrase(daysAway: Int) -> String {
        if daysAway <= 0 { return "today" }
        if daysAway == 1 { return "tomorrow" }
        return "in \(daysAway) days"
    }

    // MARK: - Computed state

    private var horizon: Horizon {
        horizonOverride ?? Horizon.defaultForHour(
            Calendar.current.component(.hour, from: Date()),
            milestones: milestones
        )
    }

    /// Project for the currently-selected horizon. Nil result means "hide";
    /// the parent already checks the default-horizon result before rendering
    /// this widget, but a tap-cycle into a wider horizon could still produce
    /// nil (band too wide) — in that case we simply render nothing.
    private var projection: CutWeightProjector.Result? {
        let now = Date()
        let days = horizon.horizonDays(activeCut: activeCut, asOf: now, calendar: .current)
        return CutWeightProjector.project(
            activeCut: activeCut,
            readings: readings,
            horizonDays: days,
            asOf: now
        )
    }

    private var isStale: Bool {
        let cal = Calendar.current
        guard let latest = readings.map(\.date).max() else { return false }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: latest), to: cal.startOfDay(for: Date())).day ?? 0
        return days > 3
    }

    /// kg → display number, rounded to one decimal.
    private func display(_ kg: Double) -> Double {
        let raw = UnitConvert.displayWeight(kg: kg, in: weightUnit)
        return (raw * 10.0).rounded() / 10.0
    }

    private var unitSym: String { weightUnit.symbol }

    // MARK: - Body

    var body: some View {
        Group {
            if let projection {
                Button(action: cycle) {
                    content(for: projection)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .accessibilityLabel(accessibilityLabel(for: projection))
                .accessibilityHint("Tap to cycle to the next time horizon")
            } else {
                // Tap-cycle landed on a horizon whose band is too wide / out
                // of range. Render an invisible tap target so the user can
                // keep cycling out of it.
                Button(action: cycle) {
                    Color.clear.frame(height: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func content(for projection: CutWeightProjector.Result) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            headlineText(for: projection)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            captionView(for: projection)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Headline (`≈ 172.1 lb in 30 days`)

    private func headlineText(for projection: CutWeightProjector.Result) -> Text {
        if projection.isFlat {
            return Text("no change projected ") + Text(horizonPhrase)
        }
        let valueStr = String(format: "%.1f %@", display(projection.projectedKg), unitSym)
        return Text("\u{2248} \(valueStr) ") + Text(horizonPhrase)
    }

    /// Trailing phrase of the headline:
    ///   * `"in 30 days"` for fixed horizons
    ///   * `"on Aug 21"` for goal-date or milestone horizons
    private var horizonPhrase: String {
        switch horizon {
        case .sevenDay, .thirtyDay, .ninetyDay:
            return horizonLabel
        case .cutGoalDate:
            return "on " + Self.monthDayFmt.string(from: activeCut.targetEndDate)
        case .milestone(let m):
            return "on " + milestoneDateString(m.date)
        }
    }

    private var horizonLabel: String {
        switch horizon {
        case .sevenDay: return "in 7 days"
        case .thirtyDay: return "in 30 days"
        case .ninetyDay: return "in 90 days"
        case .milestone, .cutGoalDate: return ""
        }
    }

    // MARK: - Caption

    /// Two pieces:
    ///   * band:   `171.0 – 173.2`   (skipped when flat)
    ///   * anchor: `goal Aug 21` for non-goal horizons, `target 158 lb` on
    ///             the goal-date horizon, or `Trip · in 12 days` on milestone
    ///             horizons (no goal anchor — the milestone IS the anchor).
    /// Stale data appends ` · stale` in tertiary color.
    @ViewBuilder
    private func captionView(for projection: CutWeightProjector.Result) -> some View {
        HStack(spacing: 0) {
            if !projection.isFlat {
                Text(bandString(for: projection))
                    .foregroundStyle(.tertiary)
                Text("  \u{B7}  ")
                    .foregroundStyle(.tertiary)
            }
            Text(anchorString)
                .foregroundStyle(.tertiary)
            if isStale {
                Text("  \u{B7}  stale")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func bandString(for projection: CutWeightProjector.Result) -> String {
        let lo = display(projection.lowerKg)
        let hi = display(projection.upperKg)
        return String(format: "%.1f \u{2013} %.1f", lo, hi)
    }

    private var anchorString: String {
        switch horizon {
        case .sevenDay, .thirtyDay, .ninetyDay:
            return "goal " + Self.monthDayFmt.string(from: activeCut.targetEndDate)
        case .cutGoalDate:
            let tgt = display(activeCut.targetWeightKg)
            return String(format: "target %.0f %@", tgt, unitSym)
        case .milestone(let m):
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let target = cal.startOfDay(for: m.date)
            let days = cal.dateComponents([.day], from: today, to: target).day ?? 0
            return "\(m.name) · \(relativeDayPhrase(daysAway: max(0, days)))"
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for projection: CutWeightProjector.Result) -> String {
        if projection.isFlat {
            return "No change projected \(horizonPhrase)."
        }
        let v = String(format: "%.1f %@", display(projection.projectedKg), unitSym)
        let lo = String(format: "%.1f", display(projection.lowerKg))
        let hi = String(format: "%.1f", display(projection.upperKg))
        return "Projected weight \(v) \(horizonPhrase). Range \(lo) to \(hi). \(anchorString)."
    }

    // MARK: - Tap

    private func cycle() {
        horizonOverride = nextHorizon(after: horizon)
    }
}
