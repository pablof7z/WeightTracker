import SwiftUI

/// A small "swipe up for meals" hint shown above the bottom safe area.
///
/// Visibility is owned by the parent (`TodayPager`) via `@AppStorage` —
/// this view just renders the indicator. Keeping the gate in one place
/// avoids two sources of truth.
struct SwipeUpHint: View {
    @State private var bouncing = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "chevron.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .offset(y: bouncing ? -3 : 2)
                .animation(
                    .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                    value: bouncing
                )
            Text("Meals")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .allowsHitTesting(false)
        .accessibilityLabel("Swipe up for meal agenda")
        .onAppear { bouncing = true }
    }
}
