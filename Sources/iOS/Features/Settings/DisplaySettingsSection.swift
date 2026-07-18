import SwiftUI

struct DisplaySettingsSection: View {
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue
    @AppStorage(AppPrefKey.theme) private var themeRaw: String = ThemePreference.system.rawValue
    @AppStorage(AppPrefKey.todayChartVariation) private var todayChartVariationRaw: String = CutChartVariation.recentFocus.rawValue
    @AppStorage(AppPrefKey.todayChartVariationOrder) private var todayChartVariationOrderRaw: String = ""

    @State private var chartOrder = CutChartVariationOrder.default

    var body: some View {
        Section {
            Picker("Weight unit", selection: $weightUnitRaw) {
                ForEach(WeightUnit.allCases, id: \.rawValue) { u in
                    Text(u.label).tag(u.rawValue)
                }
            }
            Picker("Body unit", selection: $bodyUnitRaw) {
                ForEach(BodyUnit.allCases, id: \.rawValue) { u in
                    Text(u.label).tag(u.rawValue)
                }
            }
            Picker("Theme", selection: $themeRaw) {
                ForEach(ThemePreference.allCases, id: \.rawValue) { t in
                    Text(t.label).tag(t.rawValue)
                }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Weight and body units apply throughout the app. Theme overrides the system appearance for this app only.")
        }

        Section {
            Picker("Starts on", selection: $todayChartVariationRaw) {
                ForEach(chartOrder) { variation in
                    Text(variation.label).tag(variation.rawValue)
                }
            }

            ForEach(chartOrder) { variation in
                HStack(spacing: 12) {
                    ChartVariationLegend(variation: variation)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(variation.label)
                            .font(.subheadline.weight(.medium))
                        Text(variation.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 3)
            }
            .onMove { offsets, destination in
                chartOrder.move(fromOffsets: offsets, toOffset: destination)
                todayChartVariationOrderRaw = CutChartVariationOrder.encode(chartOrder)
            }
        } header: {
            Text("Today charts")
        } footer: {
            Text("Tap Edit to arrange the swipe order. Starts on chooses the chart shown when Today opens; swiping also updates that preference.")
        }
        .onAppear {
            chartOrder = CutChartVariationOrder.decode(todayChartVariationOrderRaw)
        }
    }
}

private struct ChartVariationLegend: View {
    let variation: CutChartVariation

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.045))

                referencePath(in: size)
                    .stroke(
                        Color.secondary.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )

                projectionPath(in: size)
                    .stroke(
                        Color.accentColor.opacity(0.75),
                        style: StrokeStyle(lineWidth: 1.3, dash: [3, 2])
                    )

                dataPath(in: size)
                    .stroke(
                        Color.primary.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .frame(width: 54, height: 34)
        .accessibilityHidden(true)
    }

    private func dataPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        return Path { path in
            switch variation {
            case .fixedFullCut, .remainingToGoal, .recentFocus:
                path.move(to: CGPoint(x: 5, y: h * 0.25))
                path.addCurve(
                    to: CGPoint(x: w * 0.62, y: h * 0.62),
                    control1: CGPoint(x: w * 0.24, y: h * 0.32),
                    control2: CGPoint(x: w * 0.43, y: h * 0.54)
                )
            case .cumulativeLoss, .completionPercent:
                path.move(to: CGPoint(x: 5, y: h * 0.78))
                path.addCurve(
                    to: CGPoint(x: w * 0.62, y: h * 0.36),
                    control1: CGPoint(x: w * 0.24, y: h * 0.72),
                    control2: CGPoint(x: w * 0.43, y: h * 0.44)
                )
            case .paceDelta:
                path.move(to: CGPoint(x: 5, y: h * 0.62))
                path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.48))
                path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.57))
                path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.31))
            }
        }
    }

    private func projectionPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        return Path { path in
            switch variation {
            case .fixedFullCut, .remainingToGoal, .recentFocus:
                path.move(to: CGPoint(x: w * 0.62, y: h * 0.62))
                path.addLine(to: CGPoint(x: w - 5, y: h * 0.78))
            case .cumulativeLoss, .completionPercent:
                path.move(to: CGPoint(x: w * 0.62, y: h * 0.36))
                path.addLine(to: CGPoint(x: w - 5, y: h * 0.18))
            case .paceDelta:
                path.move(to: CGPoint(x: w * 0.62, y: h * 0.31))
                path.addLine(to: CGPoint(x: w - 5, y: h * 0.24))
            }
        }
    }

    private func referencePath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        return Path { path in
            switch variation {
            case .remainingToGoal:
                path.move(to: CGPoint(x: 4, y: h * 0.82))
                path.addLine(to: CGPoint(x: w - 4, y: h * 0.82))
            case .cumulativeLoss:
                path.move(to: CGPoint(x: 4, y: h * 0.16))
                path.addLine(to: CGPoint(x: w - 4, y: h * 0.16))
            case .paceDelta:
                path.move(to: CGPoint(x: 4, y: h * 0.5))
                path.addLine(to: CGPoint(x: w - 4, y: h * 0.5))
            case .completionPercent:
                path.move(to: CGPoint(x: 4, y: h * 0.18))
                path.addLine(to: CGPoint(x: w - 4, y: h * 0.18))
            case .recentFocus:
                path.move(to: CGPoint(x: w * 0.62, y: 4))
                path.addLine(to: CGPoint(x: w * 0.62, y: h - 4))
            case .fixedFullCut:
                path.move(to: CGPoint(x: 4, y: h * 0.78))
                path.addLine(to: CGPoint(x: w - 4, y: h * 0.78))
            }
        }
    }
}
