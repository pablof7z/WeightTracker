import SwiftUI
import SwiftData
import Charts

struct ChartView: View {
    @EnvironmentObject var services: AppServices
    @StateObject private var viewModel = ChartViewModel()

    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.lastChartRangeDays) private var rangeDays: Int = 365

    @State private var showAverage: Bool = true
    @State private var showClusters: Bool = true
    @State private var showGaps: Bool = true
    @State private var pinnedToCut: Bool = true
    @State private var colorBySleep: Bool = false
    @State private var showFullscreen: Bool = false

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }
    private var range: ChartRange {
        get { ChartRange.from(days: rangeDays) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ChartRangeButtons(
                        selection: Binding(
                            get: { ChartRange.from(days: rangeDays) },
                            set: { rangeDays = $0.rawValue }
                        ),
                        showCutPill: viewModel.activeCut != nil,
                        cutPinned: $pinnedToCut
                    )
                    .padding(.top, 8)

                    if viewModel.readings.isEmpty {
                        emptyState
                    } else {
                        WeightChart(
                            readings: viewModel.readings,
                            movingAverage: viewModel.movingAverage,
                            clusters: viewModel.clusters,
                            gaps: viewModel.gaps,
                            weightUnit: weightUnit,
                            visibleDays: effectiveVisibleDays,
                            showAverage: showAverage,
                            showClusters: showClusters,
                            showGaps: showGaps,
                            activeCut: pinnedToCut ? viewModel.activeCut : nil,
                            scrollEndDate: pinnedToCut ? viewModel.cutScrollEnd : nil,
                            colorBySleep: colorBySleep,
                            sleepLookup: { date in
                                viewModel.sleepBefore(date: date)
                            }
                        )
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                        .onTapGesture { showFullscreen = true }

                        if colorBySleep {
                            SleepOverlayLegend()
                        }
                    }

                    ChartOverlayToggles(
                        showAverage: $showAverage,
                        showClusters: $showClusters,
                        showGaps: $showGaps,
                        showSleepColor: $colorBySleep
                    )

                    Spacer(minLength: 24)
                }
            }
            .navigationTitle("Chart")
            .onAppear { viewModel.reload(from: services.repository) }
            .fullScreenCover(isPresented: $showFullscreen) {
                FullscreenChartView(
                    title: "Weight",
                    subtitle: nil,
                    series: [
                        .init(
                            name: "Actual",
                            style: .actualSolidPrimary,
                            points: viewModel.readings.map { ($0.date, $0.weightKg) }
                        ),
                        .init(
                            name: "30-day avg",
                            style: .averagePurple,
                            points: viewModel.movingAverage.map { ($0.date, $0.kg) }
                        )
                    ],
                    unit: weightUnit,
                    targetWeightKg: viewModel.activeCut?.targetWeightKg
                )
            }
        }
    }

    private var visibleDaysForRange: Int {
        let r = ChartRange.from(days: rangeDays)
        if r == .all {
            guard let first = viewModel.readings.first?.date,
                  let last = viewModel.readings.last?.date else { return 365 }
            let days = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 365
            return max(30, days)
        }
        return r.rawValue
    }

    private var effectiveVisibleDays: Int {
        if pinnedToCut, let cutDays = viewModel.cutVisibleDays {
            return cutDays
        }
        return visibleDaysForRange
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No readings yet")
                .font(.headline)
            Text("Log your first weight in the Today tab to see trends here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .glass(in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

#Preview {
    ChartView()
        .environmentObject(AppServices.shared)
}
