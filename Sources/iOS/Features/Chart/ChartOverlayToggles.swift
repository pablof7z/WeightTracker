import SwiftUI

struct ChartOverlayToggles: View {
    @Binding var showAverage: Bool
    @Binding var showClusters: Bool
    @Binding var showGaps: Bool

    var body: some View {
        HStack(spacing: 10) {
            toggle("Avg", isOn: $showAverage, color: WTColor.avgLine)
            toggle("Clusters", isOn: $showClusters, color: .blue)
            toggle("Gaps", isOn: $showGaps, color: .orange)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func toggle(_ title: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isOn.wrappedValue ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.clear),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(isOn.wrappedValue ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}
