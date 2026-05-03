import SwiftUI

/// A permanent record of every proposal and observation the coach has left,
/// including the user's replies and the outcome. Both the user and the coach
/// can refer back to this — it's the paper trail of the coaching relationship.
struct CoachHistoryView: View {
    @EnvironmentObject private var services: AppServices

    @State private var proposals: [CoachProposal] = []
    @State private var notes: [CoachNote] = []
    @State private var expandedIDs: Set<UUID> = []

    private var hasContent: Bool { !proposals.isEmpty || !notes.isEmpty }

    var body: some View {
        Group {
            if !hasContent {
                emptyState
            } else {
                List {
                    if !proposals.isEmpty {
                        Section("Proposals") {
                            ForEach(proposals, id: \.id) { proposal in
                                proposalRow(proposal)
                            }
                        }
                    }
                    if !notes.isEmpty {
                        Section("Observations") {
                            ForEach(notes, id: \.id) { note in
                                noteRow(note)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Coach History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .coachProposalDidChange)) { _ in reload() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func proposalRow(_ proposal: CoachProposal) -> some View {
        let isExpanded = expandedIDs.contains(proposal.id)
        let replies = services.coachProposalStore.replies(forProposalId: proposal.id)

        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedIDs.remove(proposal.id) }
                    else { expandedIDs.insert(proposal.id) }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            statusBadge(proposal.status)
                            Text(Self.dateFmt.string(from: proposal.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !replies.isEmpty {
                                Label("\(replies.count)", systemImage: "bubble.left")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(proposal.reasoning)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    let changes = services.coachProposalStore.changes(forProposalId: proposal.id)
                    if !changes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Changes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(changes, id: \.id) { change in
                                HStack(spacing: 6) {
                                    Image(systemName: change.accepted ? "checkmark.circle.fill" : "xmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(change.accepted ? Color.green : Color.secondary)
                                    Text(change.label)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }

                    if !replies.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your replies")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(replies, id: \.id) { reply in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "person.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(reply.body)
                                            .font(.subheadline)
                                        HStack(spacing: 4) {
                                            Text(Self.dateFmt.string(from: reply.createdAt))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            if reply.wasReadByCoach {
                                                Text("· seen by coach")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Note row

    @ViewBuilder
    private func noteRow(_ note: CoachNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.dateFmt.string(from: note.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(note.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No coach activity yet")
                .font(.headline)
            Text("Proposals and observations will appear here after the coach's first run.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func reload() {
        let cut = ActiveCutStore.load()
        proposals = cut.map { services.coachProposalStore.allProposals(forCutStartDate: $0.startDate) } ?? []
        notes = services.coachAuditStore.recentNotes(limit: 50, userVisibleOnly: true)
    }

    @ViewBuilder
    private func statusBadge(_ status: CoachProposalStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .pending:  ("Pending",  .orange)
        case .accepted: ("Accepted", .green)
        case .rejected: ("Rejected", .secondary)
        case .partial:  ("Partial",  .blue)
        }
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
