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

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }
    private var range: ChartRange {
        get { ChartRange.from(days: rangeDays) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.activeCut != nil && pinnedToCut {
                        cutPinChip
                    }

                    ChartRangeButtons(selection: Binding(
                        get: { ChartRange.from(days: rangeDays) },
                        set: {
                            rangeDays = $0.rawValue
                            pinnedToCut = false
                        }
                    ))
                    .padding(.top, 4)

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
                            scrollEndDate: pinnedToCut ? viewModel.cutScrollEnd : nil
                        )
                        .padding(.horizontal)
                    }

                    ChartOverlayToggles(
                        showAverage: $showAverage,
                        showClusters: $showClusters,
                        showGaps: $showGaps
                    )

                    Spacer(minLength: 24)
                }
            }
            .navigationTitle("Chart")
            .onAppear { viewModel.reload(from: services.repository) }
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

    private var cutPinChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "scissors")
                .foregroundStyle(.green)
            Text("Showing current cut")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Show all") {
                pinnedToCut = false
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(in: Capsule(), tint: .green.opacity(0.15))
        .padding(.horizontal)
        .padding(.top, 8)
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
