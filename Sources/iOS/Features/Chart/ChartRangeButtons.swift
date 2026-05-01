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
    var showCutPill: Bool = false
    @Binding var cutPinned: Bool

    init(selection: Binding<ChartRange>, showCutPill: Bool = false, cutPinned: Binding<Bool> = .constant(false)) {
        self._selection = selection
        self.showCutPill = showCutPill
        self._cutPinned = cutPinned
    }

    var body: some View {
        LiquidGlassContainer(spacing: 6) {
            HStack(spacing: 6) {
                if showCutPill {
                    Button {
                        cutPinned.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "scissors")
                                .font(.caption.weight(.semibold))
                            Text("Cut")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(cutPinned ? Color.white : Color.primary)
                        .glass(
                            in: Capsule(),
                            tint: cutPinned ? .green : nil
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show active cut window")
                }

                ForEach(ChartRange.allCases) { r in
                    Button {
                        selection = r
                        cutPinned = false
                    } label: {
                        Text(r.title)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle((!cutPinned && r == selection) ? Color.white : Color.primary)
                            .glass(
                                in: Capsule(),
                                tint: (!cutPinned && r == selection) ? .accentColor : nil
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
