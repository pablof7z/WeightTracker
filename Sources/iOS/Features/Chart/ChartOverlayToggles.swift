import SwiftUI

struct ChartOverlayToggles: View {
    @Binding var showAverage: Bool
    @Binding var showClusters: Bool
    @Binding var showGaps: Bool
    @Binding var showSleepColor: Bool

    var body: some View {
        LiquidGlassContainer(spacing: 10) {
            HStack(spacing: 10) {
                toggle("Avg", isOn: $showAverage, color: WTColor.avgLine)
                toggle("Clusters", isOn: $showClusters, color: .blue)
                toggle("Gaps", isOn: $showGaps, color: .orange)
                toggle("Sleep", isOn: $showSleepColor, color: .indigo, systemImage: "moon.fill")
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func toggle(
        _ title: String,
        isOn: Binding<Bool>,
        color: Color,
        systemImage: String? = nil
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                        .foregroundStyle(color)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isOn.wrappedValue ? Color.primary : Color.secondary)
            .glass(in: Capsule(), tint: isOn.wrappedValue ? color.opacity(0.2) : nil)
            .overlay(
                Capsule().strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
