import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    @EnvironmentObject var services: AppServices

    // Chart state
    @StateObject private var chartViewModel = ChartViewModel()
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.lastChartRangeDays) private var rangeDays: Int = 365
    @State private var showAverage: Bool = true
    @State private var showClusters: Bool = true
    @State private var showGaps: Bool = true
    @State private var pinnedToCut: Bool = true
    @State private var colorBySleep: Bool = false
    @State private var showFullscreen: Bool = false

    // Trends state
    @StateObject private var trendsViewModel = TrendsViewModel()
    @State private var selectedGap: Gap?

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    chartSection
                    Divider()
                        .padding(.horizontal)
                    trendsSection
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Progress")
            .onAppear {
                chartViewModel.reload(from: services.repository)
                trendsViewModel.reload(repository: services.repository)
            }
            .refreshable {
                trendsViewModel.reload(repository: services.repository)
            }
            .fullScreenCover(isPresented: $showFullscreen) {
                FullscreenChartView(
                    title: "Weight",
                    subtitle: nil,
                    series: [
                        .init(
                            name: "Actual",
                            style: .actualSolidPrimary,
                            points: chartViewModel.readings.map { ($0.date, $0.weightKg) }
                        ),
                        .init(
                            name: "30-day avg",
                            style: .averagePurple,
                            points: chartViewModel.movingAverage.map { ($0.date, $0.kg) }
                        )
                    ],
                    unit: weightUnit,
                    targetWeightKg: chartViewModel.activeCut?.targetWeightKg
                )
            }
            .sheet(item: $selectedGap) { gap in
                GapDetailSheet(gap: gap)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if chartViewModel.readings.isEmpty {
            chartEmptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ChartRangeButtons(
                    selection: Binding(
                        get: { ChartRange.from(days: rangeDays) },
                        set: { rangeDays = $0.rawValue }
                    ),
                    showCutPill: chartViewModel.activeCut != nil,
                    cutPinned: $pinnedToCut
                )
                .padding(.top, 8)

                WeightChart(
                    readings: chartViewModel.readings,
                    movingAverage: chartViewModel.movingAverage,
                    clusters: chartViewModel.clusters,
                    gaps: chartViewModel.gaps,
                    weightUnit: weightUnit,
                    visibleDays: effectiveVisibleDays,
                    showAverage: showAverage,
                    showClusters: showClusters,
                    showGaps: showGaps,
                    activeCut: pinnedToCut ? chartViewModel.activeCut : nil,
                    scrollEndDate: pinnedToCut ? chartViewModel.cutScrollEnd : nil,
                    colorBySleep: colorBySleep,
                    sleepLookup: { date in
                        chartViewModel.sleepBefore(date: date)
                    }
                )
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture { showFullscreen = true }

                if colorBySleep {
                    SleepOverlayLegend()
                }

                ChartOverlayToggles(
                    showAverage: $showAverage,
                    showClusters: $showClusters,
                    showGaps: $showGaps,
                    showSleepColor: $colorBySleep
                )
            }
        }
    }

    @ViewBuilder
    private var trendsSection: some View {
        if trendsViewModel.readings.isEmpty {
            trendsEmptyState
        } else {
            VStack(alignment: .leading, spacing: 16) {
                RightNowCard(viewModel: trendsViewModel)
                DriftBarChart(
                    gaps: trendsViewModel.gaps,
                    trendLineLb: trendsViewModel.meanGapDriftLb,
                    onSelect: { gap in selectedGap = gap }
                )
                EraSummaryTable(eras: trendsViewModel.eras)
            }
            .padding(.horizontal, 16)
        }
    }

    private var chartEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No readings yet")
                .font(.headline)
            Text("Log your first weight in the Today tab to see progress here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var trendsEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No trends yet")
                .font(.headline)
            Text("Log a few weights and your trend insights will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var visibleDaysForRange: Int {
        let r = ChartRange.from(days: rangeDays)
        if r == .all {
            guard let first = chartViewModel.readings.first?.date,
                  let last = chartViewModel.readings.last?.date else { return 365 }
            let days = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 365
            return max(30, days)
        }
        return r.rawValue
    }

    private var effectiveVisibleDays: Int {
        if pinnedToCut, let cutDays = chartViewModel.cutVisibleDays {
            return cutDays
        }
        return visibleDaysForRange
    }
}

#Preview {
    ProgressTabView()
        .environmentObject(AppServices.shared)
}
