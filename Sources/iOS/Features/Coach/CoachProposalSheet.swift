import SwiftUI
import SwiftData

/// A simpler single-proposal review sheet, used when the user taps "Apply"
/// directly on a proposal from `CoachCard` rather than entering the full
/// daily-briefing flow. Functionally equivalent to one card from
/// `CoachBriefingView` but presented as a `.sheet` with detents so it doesn't
/// take over the screen.
struct CoachProposalSheet: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    let proposal: CoachProposal

    @State private var changes: [CoachProposalChange] = []
    @State private var acceptedChanges: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(proposal.reasoning)
                        .font(.body)
                        .multilineTextAlignment(.leading)

                    Divider()

                    CoachProposalChangesView(
                        changes: changes,
                        acceptedChanges: $acceptedChanges
                    )
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                applyFooter
                    .padding()
                    .background(.ultraThinMaterial)
            }
            .navigationTitle("Coach Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            changes = Self.fetchChanges(for: proposal, container: services.modelContainer)
            acceptedChanges = Set(changes.map(\.id))
        }
    }

    private var applyFooter: some View {
        Button(action: applySelected) {
            Label(
                "Apply selected (\(acceptedChanges.count) of \(changes.count))",
                systemImage: "checkmark.circle.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .glassButtonStyle(prominent: true)
        .disabled(changes.isEmpty)
    }

    private func applySelected() {
        for change in changes {
            if acceptedChanges.contains(change.id) {
                services.coachProposalStore.acceptChange(change)
            } else {
                services.coachProposalStore.rejectChange(change)
            }
        }
        services.coachProposalStore.finalizeProposal(proposal)
        NotificationCenter.default.post(name: .coachProposalDidChange, object: nil)
        dismiss()
    }

    /// Mirror of the helper in `CoachBriefingView` — kept here so this sheet
    /// can be used independently without dragging the briefing file in.
    private static func fetchChanges(for proposal: CoachProposal, container: ModelContainer) -> [CoachProposalChange] {
        let pid = proposal.id
        let predicate = #Predicate<CoachProposalChange> { $0.proposalId == pid }
        let descriptor = FetchDescriptor<CoachProposalChange>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
}
