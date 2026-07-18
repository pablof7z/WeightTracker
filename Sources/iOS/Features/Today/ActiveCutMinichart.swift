import SwiftUI

extension Notification.Name {
    static let openCutsTab = Notification.Name("openCutsTab")
}

struct ActiveCutMinichart: View {
    let chartModel: CutChartModel
    let domains: CutChartDomainState
    let variations: [CutChartVariation]
    let unit: WeightUnit
    @Binding var variation: CutChartVariation

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

                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(Self.dateFormatter.string(from: transformed.xDomain.lowerBound)) – \(Self.dateFormatter.string(from: transformed.xDomain.upperBound))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    pageIndicator
                }
            }
            .padding(.horizontal, 16)

            TabView(selection: $variation) {
                ForEach(variations) { item in
                    StableCutChart(
                        model: CutChartTransformer.transform(
                            chartModel,
                            variation: item,
                            domains: domains
                        ),
                        unit: unit
                    )
                    .padding(.horizontal, 6)
                    .tag(item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Swipe left or right to change chart")
    }

    private var pageIndicator: some View {
        HStack(spacing: 4) {
            ForEach(variations) { item in
                Capsule()
                    .fill(item == variation ? Color.primary : Color.secondary.opacity(0.28))
                    .frame(width: item == variation ? 12 : 5, height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: variation)
    }
}
