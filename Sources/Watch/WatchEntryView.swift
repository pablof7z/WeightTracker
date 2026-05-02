import SwiftUI

struct WatchEntryView: View {
    @StateObject var viewModel = WatchEntryViewModel()
    @AppStorage(AppPrefKey.weightUnit) var unitRaw: String = "lbs"

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                VStack(spacing: 8) {
                    Text(String(format: "%.1f", viewModel.displayValue))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .focusable(true)
                        .digitalCrownRotation(
                            $viewModel.displayValue,
                            from: 50,
                            through: 500,
                            by: 0.1,
                            sensitivity: .low,
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )

                    Text(unitSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Weight")
                .accessibilityValue("\(String(format: "%.1f", viewModel.displayValue)) \(unitSymbol)")

                Button {
                    Task { await viewModel.save() }
                } label: {
                    if viewModel.saved {
                        Image(systemName: "checkmark")
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                .glassButtonStyle(prominent: true)
                .accessibilityLabel("Save weight")
                .accessibilityHint("Saves and writes to Health")
                .animation(.easeInOut(duration: 0.2), value: viewModel.saved)
            }
            .padding()
        }
    }

    private var unitSymbol: String {
        (WeightUnit(rawValue: unitRaw) ?? .lbs).symbol
    }
}
