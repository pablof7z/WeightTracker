import Foundation
import SwiftData

public extension Notification.Name {
    static let coachProposalDidChange = Notification.Name("coachProposalDidChange")
}

/// Repository for coach proposals, the per-change accept/reject decisions on
/// them, and the user's free-form replies back to the coach. Proposals are
/// scoped by `cutStartDate` so each cut has its own conversation.
@MainActor
public final class CoachProposalStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Read: Proposals

    /// All pending proposals for a cut, newest first.
    public func pendingProposals(forCutStartDate cutStartDate: Date) -> [CoachProposal] {
        let key = Reading.dayStart(of: cutStartDate)
        let pendingRaw = CoachProposalStatus.pending.rawValue
        let predicate = #Predicate<CoachProposal> {
            $0.cutStartDate == key && $0.statusRaw == pendingRaw
        }
        let descriptor = FetchDescriptor<CoachProposal>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The most recent proposal for a cut regardless of status.
    public func latestProposal(forCutStartDate cutStartDate: Date) -> CoachProposal? {
        let key = Reading.dayStart(of: cutStartDate)
        let predicate = #Predicate<CoachProposal> { $0.cutStartDate == key }
        var descriptor = FetchDescriptor<CoachProposal>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Write: Proposals & Changes

    @discardableResult
    public func create(
        cutStartDate: Date,
        reasoning: String,
        runId: UUID?
    ) -> CoachProposal {
        let proposal = CoachProposal(
            cutStartDate: cutStartDate,
            reasoning: reasoning,
            runId: runId
        )
        context.insert(proposal)
        save()
        notifyChange()
        return proposal
    }

    @discardableResult
    public func addChange(
        to proposal: CoachProposal,
        changeType: CoachProposalChangeType,
        beforeJSON: String,
        afterJSON: String,
        label: String
    ) -> CoachProposalChange {
        let nextSort = (changes(for: proposal).map(\.sortOrder).max() ?? -1) + 1
        let change = CoachProposalChange(
            proposalId: proposal.id,
            sortOrder: nextSort,
            changeType: changeType,
            beforeJSON: beforeJSON,
            afterJSON: afterJSON,
            label: label
        )
        context.insert(change)
        save()
        notifyChange()
        return change
    }

    public func acceptChange(_ change: CoachProposalChange) {
        change.accepted = true
        change.decidedAt = .now
        save()
        notifyChange()
    }

    public func rejectChange(_ change: CoachProposalChange) {
        change.accepted = false
        change.decidedAt = .now
        save()
        notifyChange()
    }

    /// Roll up the per-change decisions into the proposal's status.
    /// - All changes accepted → `.accepted`
    /// - All changes rejected (i.e. decided but none accepted) → `.rejected`
    /// - Otherwise → `.partial`
    public func finalizeProposal(_ proposal: CoachProposal) {
        let allChanges = changes(for: proposal)
        guard !allChanges.isEmpty else {
            proposal.status = .rejected
            save()
            notifyChange()
            return
        }

        let acceptedCount = allChanges.filter { $0.accepted && $0.decidedAt != nil }.count
        let rejectedCount = allChanges.filter { !$0.accepted && $0.decidedAt != nil }.count

        if acceptedCount == allChanges.count {
            proposal.status = .accepted
        } else if rejectedCount == allChanges.count {
            proposal.status = .rejected
        } else {
            proposal.status = .partial
        }
        save()
        notifyChange()
    }

    // MARK: - Read: Replies

    /// All unread replies for a cut, oldest first. Reply is associated with a
    /// cut by way of the proposal it answers; standalone replies (no proposal)
    /// are not included here because they aren't scoped to a cut.
    public func unreadReplies(forCutStartDate cutStartDate: Date) -> [CoachUserReply] {
        let proposalIds = Set(proposals(forCutStartDate: cutStartDate).map(\.id))
        guard !proposalIds.isEmpty else { return [] }

        let predicate = #Predicate<CoachUserReply> { reply in
            reply.wasReadByCoach == false
        }
        let descriptor = FetchDescriptor<CoachUserReply>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { reply in
            guard let pid = reply.proposalId else { return false }
            return proposalIds.contains(pid)
        }
    }

    // MARK: - Write: Replies

    @discardableResult
    public func recordReply(proposalId: UUID?, body: String) -> CoachUserReply {
        let reply = CoachUserReply(
            proposalId: proposalId,
            body: body
        )
        context.insert(reply)
        save()
        notifyChange()
        return reply
    }

    public func markRepliesRead(_ replies: [CoachUserReply]) {
        for reply in replies {
            reply.wasReadByCoach = true
        }
        save()
        notifyChange()
    }

    /// All changes for a specific proposal, in display order.
    public func changes(forProposalId proposalId: UUID) -> [CoachProposalChange] {
        let predicate = #Predicate<CoachProposalChange> { $0.proposalId == proposalId }
        let descriptor = FetchDescriptor<CoachProposalChange>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// All replies for a specific proposal, oldest first.
    public func replies(forProposalId proposalId: UUID) -> [CoachUserReply] {
        let predicate = #Predicate<CoachUserReply> { $0.proposalId == proposalId }
        let descriptor = FetchDescriptor<CoachUserReply>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// All proposals for a cut regardless of status, newest first.
    public func allProposals(forCutStartDate cutStartDate: Date) -> [CoachProposal] {
        proposals(forCutStartDate: cutStartDate)
    }

    // MARK: - Helpers

    private func proposals(forCutStartDate cutStartDate: Date) -> [CoachProposal] {
        let key = Reading.dayStart(of: cutStartDate)
        let predicate = #Predicate<CoachProposal> { $0.cutStartDate == key }
        let descriptor = FetchDescriptor<CoachProposal>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func changes(for proposal: CoachProposal) -> [CoachProposalChange] {
        let pid = proposal.id
        let predicate = #Predicate<CoachProposalChange> { $0.proposalId == pid }
        let descriptor = FetchDescriptor<CoachProposalChange>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        do { try context.save() } catch { print("[CoachProposalStore] save failed: \(error)") }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .coachProposalDidChange, object: nil)
    }
}
