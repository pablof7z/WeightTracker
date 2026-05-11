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
struct WeightForecastWidget: View {

    let readings: [Reading]
    let activeCut: ActiveCut
    let weightUnit: WeightUnit

    @State private var horizonOverride: Horizon?

    /// The four horizons we rotate through. Order is the tap-cycle order:
    /// `.sevenDay` → `.thirtyDay` → `.ninetyDay` → `.cutGoalDate` → `.sevenDay` …
    enum Horizon: Int, CaseIterable {
        case sevenDay = 7
        case thirtyDay = 30
        case ninetyDay = 90
        case cutGoalDate = -1   // sentinel; days are computed from the cut

        var label: String {
            switch self {
            case .sevenDay: return "in 7 days"
            case .thirtyDay: return "in 30 days"
            case .ninetyDay: return "in 90 days"
            case .cutGoalDate: return ""        // rendered as "on <date>" in body
            }
        }

        /// Pick a horizon deterministically from time-of-day. Opening at 8am
        /// and 8pm yields different horizons; two opens within the same
        /// 6-hour bucket yield the same horizon. This is the rotation
        /// mechanism — there's no timer, no animation.
        static func defaultForHour(_ hour: Int) -> Horizon {
            switch hour {
            case 0...5: return .sevenDay
            case 6...11: return .thirtyDay
            case 12...17: return .ninetyDay
            default: return .cutGoalDate
            }
        }

        func next() -> Horizon {
            let all = Self.allCases
            let idx = all.firstIndex(of: self) ?? 0
            return all[(idx + 1) % all.count]
        }

        /// Days from `asOf` to the projected date.
        func horizonDays(activeCut: ActiveCut, asOf: Date, calendar: Calendar) -> Int {
            switch self {
            case .sevenDay: return 7
            case .thirtyDay: return 30
            case .ninetyDay: return 90
            case .cutGoalDate:
                let today = calendar.startOfDay(for: asOf)
                let end = calendar.startOfDay(for: activeCut.targetEndDate)
                return max(1, calendar.dateComponents([.day], from: today, to: end).day ?? 1)
            }
        }
    }

    // MARK: - Date formatters

    private static let monthDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    // MARK: - Computed state

    private var horizon: Horizon {
        horizonOverride ?? Horizon.defaultForHour(Calendar.current.component(.hour, from: Date()))
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

    /// "in 30 days" or "on Aug 21" — the trailing phrase of the headline.
    private var horizonPhrase: String {
        switch horizon {
        case .sevenDay, .thirtyDay, .ninetyDay:
            return horizon.label
        case .cutGoalDate:
            return "on " + Self.monthDayFmt.string(from: activeCut.targetEndDate)
        }
    }

    // MARK: - Caption

    /// Two pieces:
    ///   * band:   `171.0 – 173.2`   (skipped when flat)
    ///   * anchor: `goal Aug 21` for non-goal horizons, or `target 158 lb`
    ///             when this IS the goal-date horizon.
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
        horizonOverride = horizon.next()
    }
}
