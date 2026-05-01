import SwiftUI
import SwiftData

struct TrendsView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = TrendsViewModel()
    @State private var selectedGap: Gap?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.readings.isEmpty {
                        emptyState
                    } else {
                        RightNowCard(viewModel: viewModel)
                        DriftBarChart(
                            gaps: viewModel.gaps,
                            trendLineLb: viewModel.meanGapDriftLb,
                            onSelect: { gap in selectedGap = gap }
                        )
                        EraSummaryTable(eras: viewModel.eras)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Trends")
            .onAppear { viewModel.reload(repository: services.repository) }
            .refreshable { viewModel.reload(repository: services.repository) }
            .sheet(item: $selectedGap) { gap in
                GapDetailSheet(gap: gap)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var emptyState: some View {
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
        .glass(in: RoundedRectangle(cornerRadius: 16))
    }
}
