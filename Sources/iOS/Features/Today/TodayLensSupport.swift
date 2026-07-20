import SwiftUI

/// Posted when something wants Today to surface the start-a-cut flow. Relocated
/// here when the orphaned `ActiveCutMinichart` was removed; `TodayView` is the
/// only observer.
extension Notification.Name {
    static let openCutsTab = Notification.Name("openCutsTab")
}

/// Weight entry surfaced from a long-press on the lens hero (a tap toggles the
/// unit). Presents the normal decimal keyboard, keeps fine ± nudges, and routes
/// through the existing `TodayViewModel.save` pipeline — HealthKit, coach, and
/// notification side effects are unchanged.
struct LogWeightSheet: View {
    @Binding var displayValue: Double
    let unit: WeightUnit
    let date: Date
    let hasEntry: Bool
    let subtitle: String
    var onUnitTap: () -> Void
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    private static let titleFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()
    private var titleText: String {
        Calendar.current.isDateInToday(date) ? "Today" : Self.titleFmt.string(from: date)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("", text: $text)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .fixedSize()
                        .onChange(of: text) { _, value in
                            if let d = Double(value.replacingOccurrences(of: ",", with: ".")) {
                                displayValue = (d * 10).rounded() / 10
                            }
                        }
                    Button(action: onUnitTap) {
                        Text(unit.symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unit \(unit.symbol). Tap to switch.")
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 24) {
                    nudge("minus", by: -0.1)
                    nudge("plus", by: 0.1)
                }

                Button(action: onSave) {
                    Text(hasEntry ? "Update" : "Log Weight")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                text = String(format: "%.1f", displayValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
            }
            .onChange(of: unit) { _, _ in
                text = String(format: "%.1f", displayValue)
            }
        }
    }

    private func nudge(_ symbol: String, by amount: Double) -> some View {
        Button {
            displayValue = (((displayValue + amount) * 10).rounded() / 10)
            text = String(format: "%.1f", displayValue)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 64, height: 48)
                .glass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
    }
}

/// The deeper inspection chart, opened by a deliberate tap on a Today lens. It
/// reuses the exact same prepared `CutChartModel` and domains as the lenses —
/// no separately computed truth — and exposes the full landscape focus chart
/// with visible axes.
struct LensDetailCover: View {
    let chartModel: CutChartModel
    let domains: CutChartDomainState
    let unit: WeightUnit
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LandscapeFocusChart(chartModel: chartModel, domains: domains, unit: unit)
                .ignoresSafeArea()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .glassCircle()
            }
            .padding(20)
            .accessibilityLabel("Close detail chart")
        }
    }
}
