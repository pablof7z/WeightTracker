import SwiftUI

struct CutsView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel = CutsViewModel()
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @State private var showStartSheet = false
    @State private var showEditSheet = false
    @State private var showCoachAudit = false

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
                            Label("Start a Cut", systemImage: "plus")
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
            .sheet(isPresented: $showCoachAudit) {
                auditSheet
            }
            .onAppear { viewModel.reload() }
            .onReceive(services.cutCoach.$recommendation) { recommendation in
                viewModel.applyCutCoachRecommendation(recommendation)
            }
            .refreshable { viewModel.reload() }
        }
    }

    @ViewBuilder
    private var activeSection: some View {
        if let cut = viewModel.activeCut {
            VStack(spacing: 16) {
                ActiveCutCard(
                    cut: cut,
                    actualRateLbPerWeek: viewModel.actualRateLbPerWeek(),
                    neededRateLbPerWeek: viewModel.neededRateLbPerWeek(),
                    status: viewModel.status(),
                    projectedEndWeightKg: viewModel.projectedEndWeightKg(),
                    unit: unit,
                    readings: viewModel.allReadings,
                    projection: viewModel.projection
                ) {
                    Task { await viewModel.markDone() }
                }

                if let plan = viewModel.cutCoachPlan {
                    CutCoachCard(
                        plan: plan,
                        onShowAudit: { showCoachAudit = true }
                    )
                }

                MacroCard(cutStartDate: cut.startDate)
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
                if viewModel.mostRecentReading == nil {
                    Text("Log a weight in the Today tab first — your latest reading becomes the starting point.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .glass(in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var auditSheet: some View {
        CoachAuditSheet()
            .environmentObject(services)
    }

    @ViewBuilder
    private var historicalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Historical Cuts")
                .font(.headline)
            if viewModel.historicalCuts.isEmpty {
                Text("Past weight-loss runs appear here automatically once enough history is logged.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glass(in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(viewModel.historicalCuts) { cut in
                    HistoricalCutCard(
                        cut: cut,
                        unit: unit,
                        readings: viewModel.allReadings
                    )
                }
            }
        }
    }
}
