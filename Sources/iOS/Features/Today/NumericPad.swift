import SwiftUI
import Combine

struct NumericPad: View {
    @Binding var value: Double
    let unitSymbol: String
    var tapStep: Double = 0.1
    var longPressStep: Double = 1.0
    var controlsVisible: Bool = true
    var onValueTap: (() -> Void)? = nil
    var onUnitTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Button {
                onValueTap?()
            } label: {
                Text(formatted)
                    .font(.system(size: 96, weight: .black, design: .default))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(onValueTap == nil)
            .accessibilityLabel(onValueTap != nil ? "Current weight \(formatted) \(unitSymbol). Tap to edit." : "Current weight \(formatted) \(unitSymbol).")

            Button {
                onUnitTap?()
            } label: {
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
            .buttonStyle(.plain)
            .disabled(onUnitTap == nil)
            .accessibilityLabel(onUnitTap != nil ? "Current unit \(unitSymbol). Tap to switch unit." : "Current unit \(unitSymbol).")

            if controlsVisible {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
            .foregroundStyle(.primary)
            .frame(width: 72, height: 56)
            .glass(in: Capsule())
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
