import SwiftUI

struct CutProjectionChartContent: View {
    let chartModel: CutChartModel
    let domains: CutChartDomainState
    let unit: WeightUnit
    var height: CGFloat = 96
    var hideXAxisLabels: Bool = false

    private var transformed: TransformedCutChartModel {
        CutChartTransformer.transform(chartModel, variation: .fixedFullCut, domains: domains)
    }

    var body: some View {
        StableCutChart(
            model: transformed,
            unit: unit,
            showXAxis: !hideXAxisLabels
        )
        .frame(height: height)
    }
}
