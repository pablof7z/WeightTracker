import SwiftUI

struct CutsView: View {
    @StateObject private var viewModel = CutsViewModel()
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @State private var showStartSheet = false
    @State private var showEditSheet = false

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    activeSection
                    historicalSection
                }
                .padding()
            }
            .navigationTitle("Cuts")
            .toolbar {
                if viewModel.activeCut == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showStartSheet = true
                        } label: {
                            Label("Start Cut", systemImage: "plus")
                        }
                        .disabled(viewModel.mostRecentReading == nil)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: $showStartSheet) {
                if let recent = viewModel.mostRecentReading {
                    StartCutSheet(startWeightKg: recent.weightKg) { cut in
                        Task { await viewModel.startCut(cut) }
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let active = viewModel.activeCut {
                    EditCutSheet(
                        cut: active,
                        onSave: { updated in
                            Task { await viewModel.updateCut(updated) }
                        },
                        onCancelCut: {
                            Task { await viewModel.markDone() }
                        }
                    )
                }
            }
            .onAppear { viewModel.reload() }
            .refreshable { viewModel.reload() }
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        if let cut = viewModel.activeCut {
            ActiveCutCard(
                cut: cut,
                actualRateLbPerWeek: viewModel.actualRateLbPerWeek(),
                neededRateLbPerWeek: viewModel.neededRateLbPerWeek(),
                status: viewModel.status(),
                projectedEndWeightKg: viewModel.projectedEndWeightKg(),
                unit: unit
            ) {
                Task { await viewModel.markDone() }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("No active cut", systemImage: "scissors")
                    .font(.headline)
                Text("Start a cut to track your progress toward a target weight with a daily reminder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showStartSheet = true
                } label: {
                    Label("Start a Cut", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.mostRecentReading == nil)
                .padding(.top, 4)
            }
            .padding()
            .glass(in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var historicalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Historical Cuts")
                .font(.headline)
            if viewModel.historicalCuts.isEmpty {
                Text("None detected yet. Cuts of at least 10 days at 0.5 lb/wk or more will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.historicalCuts) { cut in
                    HistoricalCutCard(
                        cut: cut,
                        unit: unit,
                        yearsAgo: viewModel.yearsAgo(of: cut.startDate)
                    )
                }
            }
        }
    }
}
