import SwiftUI

/// "Estimated cut progress" widget — two numbers:
///   1. Cumulative caloric deficit since the cut start (gates day 7+).
///   2. Recent daily deficit rate over a trailing 14-day window (gates day 14+).
///
/// Display rules — see `/tmp/cut-tracker-deficit-research-ux.md`:
///   - Neutral text colors only. NO green/red. Punitive coloring triggers
///     shame spirals; MacroFactor deliberately avoids it.
///   - Cumulative rounded to nearest 500 kcal, formatted `~8,500 kcal`.
///   - Daily rate rounded to nearest 50 kcal/day, formatted `≈ 450 kcal/day`.
///     Surplus shown as `≈ +120 kcal/day surplus` (neutral, no shame).
///   - Always-visible footnote: "Estimated from weight trend. Not based on
///     logged intake."
///   - Tap a number → "How we calculate this" sheet.
struct CutDeficitWidget: View {
    let result: CutDeficitEstimator.Result
    let cutStartDate: Date

    @State private var showExplainer = false

    private static let startDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let groupedFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Estimated cut progress")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                cumulativeColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 36)

                dailyRateColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Estimated from weight trend. Not based on logged intake.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .sheet(isPresented: $showExplainer) {
            CutDeficitExplainerSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Cumulative column

    @ViewBuilder
    private var cumulativeColumn: some View {
        Button {
            showExplainer = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                cumulativeValueText
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(cumulativeCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows how the deficit is calculated")
    }

    private var cumulativeValueText: Text {
        switch result.cumulativeState {
        case .calibrating:
            return Text("Calibrating")
        case .noActiveCut:
            return Text("—")
        case .active:
            guard let kcal = result.cumulativeDeficitKcal else { return Text("—") }
            return Text(formatCumulative(kcal))
        }
    }

    private var cumulativeCaption: String {
        if case .calibrating(let n) = result.cumulativeState {
            return "\(n) more day\(n == 1 ? "" : "s")"
        }
        let dateStr = Self.startDateFmt.string(from: cutStartDate)
        if let kcal = result.cumulativeDeficitKcal, kcal < 0 {
            return "Estimated surplus since \(dateStr)"
        }
        return "Estimated deficit since \(dateStr)"
    }

    // MARK: - Daily rate column

    @ViewBuilder
    private var dailyRateColumn: some View {
        Button {
            showExplainer = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                dailyRateValueText
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(dailyRateCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows how the recent rate is calculated")
    }

    private var dailyRateValueText: Text {
        switch result.dailyRateState {
        case .calibrating:
            return Text("Calibrating")
        case .noActiveCut:
            return Text("—")
        case .active:
            guard let kcal = result.dailyDeficitKcalPerDay else { return Text("—") }
            return Text(formatDailyRate(kcal))
        }
    }

    private var dailyRateCaption: String {
        if case .calibrating(let n) = result.dailyRateState {
            return "\(n) more day\(n == 1 ? "" : "s")"
        }
        return "Recent rate · last 14 days"
    }

    // MARK: - Formatting

    /// `~8,500 kcal`. Round to nearest 500. Sign is implicit; surplus uses the
    /// caption ("Estimated surplus since…") rather than a sign on the number.
    private func formatCumulative(_ kcal: Double) -> String {
        let magnitude = abs(kcal)
        let rounded = (magnitude / 500.0).rounded() * 500.0
        let str = Self.groupedFmt.string(from: NSNumber(value: rounded)) ?? "\(Int(rounded))"
        return "~\(str) kcal"
    }

    /// `≈ 450 kcal/day` for deficit; `≈ +120 kcal/day surplus` for surplus.
    /// Round to nearest 50. We display surplus inline so the column reads as
    /// a single thought without forcing the caption to carry the sign.
    private func formatDailyRate(_ kcal: Double) -> String {
        let rounded = (kcal / 50.0).rounded() * 50.0
        let magnitude = Int(abs(rounded))
        let mag = Self.groupedFmt.string(from: NSNumber(value: magnitude)) ?? "\(magnitude)"
        if rounded < 0 {
            return "≈ +\(mag) kcal/day surplus"
        }
        return "≈ \(mag) kcal/day"
    }
}

// MARK: - Explainer sheet

struct CutDeficitExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(
                        title: "Cumulative deficit",
                        body: "We compare the smoothed weight trend on your cut start day to today's smoothed trend, and multiply the difference by the energy density below. Trend, not raw scale numbers, so a single noisy weigh-in doesn't distort it."
                    )
                    section(
                        title: "Recent rate",
                        body: "We fit a straight line to the smoothed weight trend over the last 14 days and convert the slope to kcal/day. Two weeks of slope is the shortest window where day-to-day water swings stop dominating the signal."
                    )
                    section(
                        title: "Energy density",
                        body: "We use 3,000 kcal per lb of body-weight change — a mix of fat and lean tissue, not pure fat. Real metabolism varies ±20%."
                    )
                    section(
                        title: "Calibration period",
                        body: "Cumulative needs 7 days, daily rate needs 14 days, before we trust the smoothing. Until then we hide the number rather than show something misleading."
                    )
                    Text("Estimated from weight trend. Not based on logged intake.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("How we calculate this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
