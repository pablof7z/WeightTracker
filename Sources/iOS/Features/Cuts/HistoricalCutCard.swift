import SwiftUI

struct HistoricalCutCard: View {
    let cut: HistoricalCut
    let unit: WeightUnit
    let yearsAgo: Int

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(Self.dateFmt.string(from: cut.startDate)) → \(Self.dateFmt.string(from: cut.endDate))")
                    .font(.subheadline).bold()
                Spacer()
                Text("\(cut.durationDays)d")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }

            HStack(spacing: 16) {
                metric(title: "Loss", value: formatLoss())
                metric(title: "Avg rate", value: formatRate())
                metric(title: "When", value: yearsAgoLabel)
            }
        }
        .padding()
        .glass(in: RoundedRectangle(cornerRadius: 12))
    }

    private var yearsAgoLabel: String {
        if yearsAgo == 0 { return "this year" }
        if yearsAgo == 1 { return "1y ago" }
        return "\(yearsAgo)y ago"
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body).bold().monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatLoss() -> String {
        if unit == .lbs {
            return String(format: "%.1f lb", cut.totalLossLb)
        } else {
            return String(format: "%.1f kg", cut.totalLossKg)
        }
    }

    private func formatRate() -> String {
        if unit == .lbs {
            return String(format: "%.1f lb/wk", cut.avgRateLbPerWeek)
        } else {
            return String(format: "%.1f kg/wk", cut.avgRateKgPerWeek)
        }
    }
}
