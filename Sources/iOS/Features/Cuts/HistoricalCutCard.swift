import SwiftUI

struct HistoricalCutCard: View {
    let cut: HistoricalCut
    let unit: WeightUnit
    var readings: [Reading] = []

    @State private var showFullscreen = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static let relativeFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
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
                    .accessibilityLabel("Duration \(cut.durationDays) days")
            }

            HStack(spacing: 16) {
                metric(title: "Loss", value: formatLoss())
                metric(title: "Avg rate", value: formatRate())
                metric(title: "When", value: yearsAgoLabel)
            }

            CutInlineChart(
                readings: readings,
                startDate: cut.startDate,
                endDate: cut.endDate,
                unit: unit,
                startWeightKg: cut.startWeightKg
            )
            .padding(.top, 4)
            .contentShape(Rectangle())
            .onTapGesture { showFullscreen = true }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .fullScreenCover(isPresented: $showFullscreen) {
            let cutReadings = readings.filter { $0.date >= cut.startDate && $0.date <= cut.endDate }
            FullscreenChartView(
                title: "Cut",
                subtitle: "\(Self.dateFmt.string(from: cut.startDate)) → \(Self.dateFmt.string(from: cut.endDate))",
                series: [
                    .init(name: "Actual", style: .actualSolidPrimary, points: cutReadings.map { ($0.date, $0.weightKg) })
                ],
                unit: unit,
                targetWeightKg: cut.endWeightKg
            )
        }
    }

    private var yearsAgoLabel: String {
        Self.relativeFmt.localizedString(for: cut.startDate, relativeTo: Date())
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
