import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    /// When embedded (pushed onto another NavigationStack, e.g. from Today),
    /// omit the internal NavigationStack so it doesn't nest.
    var embedded: Bool = false

    @EnvironmentObject var services: AppServices

    // Chart state
    @StateObject private var chartViewModel = ChartViewModel()
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.lastChartRangeDays) private var rangeDays: Int = 365
    @AppStorage(AppPrefKey.cycleAdjustmentEnabled) private var cycleEnabled: Bool = false
    @State private var showAverage: Bool = true
    @State private var showClusters: Bool = true
    @State private var showGaps: Bool = true
    @State private var pinnedToCut: Bool = true
    @State private var colorBySleep: Bool = false

    // Trends state
    @StateObject private var trendsViewModel = TrendsViewModel()
    @State private var selectedGap: Gap?
    @State private var showWeightLog = false
    @State private var showConversations = false
    @State private var activeCut: ActiveCut?

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    chartSection
                    Divider()
                        .padding(.horizontal)
                    trendsSection
                    Divider()
                        .padding(.horizontal)
                    planSection
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(embedded ? .inline : .automatic)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showWeightLog = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Weight log")
                }
            }
            .sheet(isPresented: $showWeightLog, onDismiss: {
                chartViewModel.reload(from: services.repository)
                trendsViewModel.reload(repository: services.repository)
            }) {
                WeightLogView()
                    .environmentObject(services)
            }
            .sheet(isPresented: $showConversations) {
                CoachConversationsView()
                    .environmentObject(services)
                    .presentationDetents([.large])
            }
            .onAppear {
                chartViewModel.reload(from: services.repository)
                trendsViewModel.reload(repository: services.repository)
                activeCut = ActiveCutStore.load()
            }
            .refreshable {
                trendsViewModel.reload(repository: services.repository)
            }
            .sheet(item: $selectedGap) { gap in
                GapDetailSheet(gap: gap)
                    .presentationDetents([.medium, .large])
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
                    },
                    cycleStarts: services.cycleStarts,
                    showCycleBands: cycleEnabled
                )
                .padding(.horizontal)

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

    // MARK: - Plan & Coach (rehomed from the retired Cuts/Coach tabs)

    @ViewBuilder
    private var planSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let cut = activeCut {
                MacroCard(cutStartDate: cut.startDate)
                MealPlanCard(cutStartDate: cut.startDate)
                ActivityCard()
            }

            Button {
                showConversations = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coach conversations")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Chat, voice notes, and plan proposals")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
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
