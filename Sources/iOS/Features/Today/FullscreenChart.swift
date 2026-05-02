import SwiftUI
import Charts

public struct FullscreenChartView: View {
    public struct Series: Identifiable {
        public let id = UUID()
        public let name: String
        public let style: SeriesStyle
        public let points: [(Date, Double)]

        public init(name: String, style: SeriesStyle, points: [(Date, Double)]) {
            self.name = name
            self.style = style
            self.points = points
        }
    }

    public enum SeriesStyle {
        case actualSolidPrimary
        case projectionDashedGreen
        case projectionDashedRed
        case projectionSolidBlue
        case averagePurple
        case generalSecondary

        var color: Color {
            switch self {
            case .actualSolidPrimary: return .primary
            case .projectionDashedGreen: return .green
            case .projectionDashedRed: return Color(red: 0.78, green: 0.30, blue: 0.30)
            case .projectionSolidBlue: return .blue
            case .averagePurple: return .purple
            case .generalSecondary: return .secondary
            }
        }

        var dash: [CGFloat]? {
            switch self {
            case .projectionDashedGreen, .projectionDashedRed: return [4, 3]
            case .actualSolidPrimary, .projectionSolidBlue, .averagePurple, .generalSecondary: return nil
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .projectionDashedGreen, .projectionDashedRed: return 1.5
            default: return 2
            }
        }
    }

    let title: String
    let subtitle: String?
    let series: [Series]
    let unit: WeightUnit
    var targetWeightKg: Double? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date?
    @State private var visibleSpanDays: Double = 0   // 0 = "all"
    @State private var initialDomainSet = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private func display(_ kg: Double) -> Double {
        UnitConvert.displayWeight(kg: kg, in: unit)
    }

    private var allPoints: [(Date, Double)] { series.flatMap(\.points) }

    private var firstDate: Date {
        allPoints.map(\.0).min() ?? Date()
    }
    private var lastDate: Date {
        allPoints.map(\.0).max() ?? Date()
    }

    private var fullSpanDays: Double {
        max(1, lastDate.timeIntervalSince(firstDate) / 86_400)
    }

    private var effectiveSpanDays: Double {
        visibleSpanDays > 0 ? min(visibleSpanDays, fullSpanDays) : fullSpanDays
    }

    private var yValues: [Double] { allPoints.map { display($0.1) } }
    private var yMin: Double { (yValues.min() ?? 0) - 1.5 }
    private var yMax: Double { (yValues.max() ?? 100) + 1.5 }

    private func selection(for date: Date) -> (series: Series, point: (Date, Double))? {
        var best: (series: Series, point: (Date, Double), dt: TimeInterval)? = nil
        for s in series {
            guard let p = s.points.min(by: { abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date)) }) else { continue }
            let dt = abs(p.0.timeIntervalSince(date))
            if best == nil || dt < best!.dt {
                best = (s, p, dt)
            }
        }
        guard let b = best else { return nil }
        return (b.series, b.point)
    }

    public var body: some View {
        NavigationStack {
            LiquidGlassContainer(spacing: 8) {
                VStack(spacing: 0) {
                    if let sel = selectedDate, let hit = selection(for: sel) {
                        selectionBanner(date: hit.point.0, kg: hit.point.1, seriesName: hit.series.name, color: hit.series.style.color)
                    } else {
                        placeholderBanner
                    }

                    Chart {
                        if let target = targetWeightKg {
                            RuleMark(y: .value("Target", display(target)))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .foregroundStyle(.gray.opacity(0.6))
                                .annotation(position: .topTrailing, alignment: .trailing) {
                                    Text("Target \(String(format: "%.1f", display(target))) \(unit.symbol)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                        }

                        ForEach(series) { s in
                            let dash = s.style.dash
                            let stroke: StrokeStyle = dash.map { StrokeStyle(lineWidth: s.style.lineWidth, dash: $0) } ?? StrokeStyle(lineWidth: s.style.lineWidth)
                            ForEach(Array(s.points.enumerated()), id: \.offset) { _, p in
                                LineMark(
                                    x: .value("Date", p.0),
                                    y: .value("Weight", display(p.1)),
                                    series: .value("series", s.name)
                                )
                                .interpolationMethod(.linear)
                                .lineStyle(stroke)
                                .foregroundStyle(s.style.color)
                            }
                            if dash == nil {
                                ForEach(Array(s.points.enumerated()), id: \.offset) { _, p in
                                    PointMark(
                                        x: .value("Date", p.0),
                                        y: .value("Weight", display(p.1))
                                    )
                                    .symbolSize(14)
                                    .foregroundStyle(s.style.color)
                                }
                            }
                        }

                        if let sel = selectedDate {
                            RuleMark(x: .value("sel", sel))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                    }
                    .chartXScale(domain: firstDate...lastDate)
                    .chartYScale(domain: yMin...yMax)
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: effectiveSpanDays * 86_400)
                    .chartXSelection(value: $selectedDate)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(v.rounded())) \(unit.symbol)")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxHeight: .infinity)

                    zoomBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    seriesLegend
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(id: "fullscreen-subtitle", placement: .principal) {
                        if let subtitle {
                            VStack(spacing: 0) {
                                Text(title).font(.headline)
                                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if !initialDomainSet {
                visibleSpanDays = fullSpanDays
                initialDomainSet = true
            }
            AppOrientation.shared.set(.landscape)
        }
        .onDisappear {
            AppOrientation.shared.set(.portrait)
        }
    }

    private var zoomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { 1.0 - (effectiveSpanDays / fullSpanDays) },
                    set: { newVal in
                        let zoomFactor = max(0.001, 1.0 - newVal)
                        visibleSpanDays = max(7, fullSpanDays * zoomFactor)
                    }
                )
            )
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
        }
    }

    private func selectionBanner(date: Date, kg: Double, seriesName: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFmt.string(from: date))
                    .font(.subheadline.weight(.semibold))
                Text(seriesName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.1f %@", display(kg), unit.symbol))
                .font(.title3.bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(in: Rectangle())
    }

    private var placeholderBanner: some View {
        HStack {
            Text("Drag across the chart to inspect a value")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(in: Rectangle())
    }

    private var seriesLegend: some View {
        HStack(spacing: 12) {
            ForEach(series) { s in
                HStack(spacing: 4) {
                    Circle().fill(s.style.color).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(s.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
