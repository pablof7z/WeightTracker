import SwiftUI
import Combine

struct NumericPad: View {
    @Binding var value: Double
    let unitSymbol: String
    /// Step for tap (default ±0.1)
    var tapStep: Double = 0.1
    /// Step for long-press (default ±1.0)
    var longPressStep: Double = 1.0
    /// Optional: tap on the number to toggle unit
    var onUnitTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Button {
                onUnitTap?()
            } label: {
                VStack(spacing: 4) {
                    Text(formatted)
                        .font(.system(size: 96, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text(unitSymbol)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                        if onUnitTap != nil {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(onUnitTap == nil)
            .accessibilityLabel(onUnitTap != nil ? "Current weight \(formatted) \(unitSymbol). Tap to switch unit." : "Current weight \(formatted) \(unitSymbol).")

            LiquidGlassContainer(spacing: 28) {
                HStack(spacing: 28) {
                    PadButton(symbol: "minus") {
                        value = clamped(round1(value - tapStep))
                    } onLongPressTick: {
                        value = clamped(round1(value - longPressStep))
                    }

                    PadButton(symbol: "plus") {
                        value = clamped(round1(value + tapStep))
                    } onLongPressTick: {
                        value = clamped(round1(value + longPressStep))
                    }
                }
            }
            .padding(.top, 8)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: value)
        .sensoryFeedback(.selection, trigger: unitSymbol)
    }

    private var formatted: String {
        String(format: "%.1f", value)
    }

    private func round1(_ x: Double) -> Double { (x * 10.0).rounded() / 10.0 }
    private func clamped(_ x: Double) -> Double { min(max(x, 10.0), 999.0) }
}

private struct PadButton: View {
    let symbol: String
    let onTap: () -> Void
    let onLongPressTick: () -> Void

    @State private var isPressing = false
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: 72, height: 56)
            .glass(in: Capsule(), tint: .accentColor.opacity(0.25))
            .contentShape(Capsule())
            .onTapGesture { onTap() }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in startRepeating() }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in stopRepeating() }
            )
            .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
            .scaleEffect(isPressing ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressing)
            .onDisappear { stopRepeating() }
    }

    private func startRepeating() {
        guard timer == nil else { return }
        isPressing = true
        // Fire one immediately on long-press start
        onLongPressTick()
        let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in onLongPressTick() }
        }
        timer = t
    }

    private func stopRepeating() {
        isPressing = false
        timer?.invalidate()
        timer = nil
    }
}
