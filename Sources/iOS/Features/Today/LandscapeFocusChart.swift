import SwiftUI

/// Landscape presentation of the shared fixed full-cut chart. It intentionally
/// keeps the same immutable domains and prepared series as the compact chart;
/// only its annotations and available plotting area differ.
struct LandscapeFocusChart: View {
    let chartModel: CutChartModel
    let domains: CutChartDomainState
    let unit: WeightUnit

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private var transformed: TransformedCutChartModel {
        CutChartTransformer.transform(chartModel, variation: .fixedFullCut, domains: domains)
    }

    private func weight(_ pounds: Double) -> String {
        let value = unit == .lbs ? pounds : UnitConvert.lbToKg(pounds)
        return String(format: "%.1f %@", value, unit.symbol)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            StableCutChart(model: transformed, unit: unit, showXAxis: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Full cut weight")
                            .font(.headline)
                        if let latest = chartModel.trailing7.last?.value {
                            Text("\(weight(latest)) trailing 7-day trend")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Self.dateFormatter.string(from: chartModel.startDate)) – \(Self.dateFormatter.string(from: chartModel.targetDate))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .glass(in: RoundedRectangle(cornerRadius: 12))

                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 52)
            .padding(.top, 12)
        }
    }
}
