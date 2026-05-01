import SwiftUI

struct SleepOverlayLegend: View {
    private struct Item: Identifiable {
        let id = UUID()
        let color: Color
        let label: String
    }

    private let items: [Item] = [
        .init(color: Color.red.opacity(0.85), label: "<5h"),
        .init(color: Color.orange.opacity(0.85), label: "5–6.5"),
        .init(color: Color.yellow.opacity(0.85), label: "6.5–7.5"),
        .init(color: Color.green.opacity(0.85), label: "≥7.5"),
        .init(color: Color.gray.opacity(0.5), label: "—")
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)
                    Text(item.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glass(in: Capsule())
        .padding(.horizontal)
    }
}

#Preview {
    SleepOverlayLegend()
}
