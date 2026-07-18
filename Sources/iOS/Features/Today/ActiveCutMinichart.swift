import SwiftUI

extension Notification.Name {
    static let openCutsTab = Notification.Name("openCutsTab")
}

struct ActiveCutMinichart: View {
    let chartModel: CutChartModel
    let domains: CutChartDomainState
    let variation: CutChartVariation
    let unit: WeightUnit

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private var transformed: TransformedCutChartModel {
        CutChartTransformer.transform(chartModel, variation: variation, domains: domains)
    }

    private var latestValueText: String? {
        guard let valueLb = transformed.latestTrendValue else { return nil }
        switch variation {
        case .completionPercent:
            return String(format: "%.0f%% complete", valueLb)
        case .paceDelta:
            let displayValue = unit == .lbs ? valueLb : UnitConvert.lbToKg(valueLb)
            let direction = displayValue >= 0 ? "ahead" : "behind"
            return String(format: "%.1f %@ %@", abs(displayValue), unit.symbol, direction)
        case .remainingToGoal:
            let displayValue = unit == .lbs ? valueLb : UnitConvert.lbToKg(valueLb)
            return String(format: "%.1f %@ remaining", displayValue, unit.symbol)
        case .cumulativeLoss:
            let displayValue = unit == .lbs ? valueLb : UnitConvert.lbToKg(valueLb)
            return String(format: "%.1f %@ lost", displayValue, unit.symbol)
        case .fixedFullCut, .recentFocus:
            let displayValue = unit == .lbs ? valueLb : UnitConvert.lbToKg(valueLb)
            return String(format: "%.1f %@ trend", displayValue, unit.symbol)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(variation.label)
                        .font(.caption.weight(.semibold))
                    if let latestValueText {
                        Text(latestValueText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(Self.dateFormatter.string(from: transformed.xDomain.lowerBound)) – \(Self.dateFormatter.string(from: transformed.xDomain.upperBound))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            StableCutChart(model: transformed, unit: unit)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .accessibilityElement(children: .contain)
    }
}
