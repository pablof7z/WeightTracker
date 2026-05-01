import SwiftUI

enum ChartRange: Int, CaseIterable, Identifiable {
    case sixMonths = 180
    case oneYear = 365
    case twoYears = 730
    case fiveYears = 1825
    case all = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sixMonths: return "6m"
        case .oneYear: return "1y"
        case .twoYears: return "2y"
        case .fiveYears: return "5y"
        case .all: return "All"
        }
    }

    static func from(days: Int) -> ChartRange {
        ChartRange(rawValue: days) ?? .oneYear
    }
}

struct ChartRangeButtons: View {
    @Binding var selection: ChartRange

    var body: some View {
        LiquidGlassContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(ChartRange.allCases) { r in
                    Button {
                        selection = r
                    } label: {
                        Text(r.title)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(r == selection ? Color.white : Color.primary)
                            .glass(
                                in: Capsule(),
                                tint: r == selection ? .accentColor : nil
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Range \(r.title)")
                }
            }
        }
        .padding(.horizontal)
    }
}
