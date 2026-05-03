import Foundation
import SwiftData

// MARK: - Enums

public enum CoachProposalStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
    case partial
}

public enum CoachProposalChangeType: String, Codable, CaseIterable, Sendable {
    case macroPlan
    case mealSchedule
    case stepTarget
    case other
}

// MARK: - CoachProposal

@Model
public final class CoachProposal {
    @Attribute(.unique) public var id: UUID
    public var cutStartDate: Date
    public var createdAt: Date
    public var reasoning: String
    public var statusRaw: String = "pending"
    public var runId: UUID?

    public init(
        id: UUID = UUID(),
        cutStartDate: Date,
        createdAt: Date = .now,
        reasoning: String,
        status: CoachProposalStatus = .pending,
        runId: UUID? = nil
    ) {
        self.id = id
        self.cutStartDate = Reading.dayStart(of: cutStartDate)
        self.createdAt = createdAt
        self.reasoning = reasoning
        self.statusRaw = status.rawValue
        self.runId = runId
    }

    public var status: CoachProposalStatus {
        get { CoachProposalStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - CoachProposalChange

@Model
public final class CoachProposalChange {
    @Attribute(.unique) public var id: UUID
    public var proposalId: UUID
    public var sortOrder: Int = 0
    public var changeTypeRaw: String = "other"
    public var beforeJSON: String = "pending"
    public var afterJSON: String = "pending"
    public var label: String = "pending"
    public var accepted: Bool = false
    public var decidedAt: Date?

    public init(
        id: UUID = UUID(),
        proposalId: UUID,
        sortOrder: Int = 0,
        changeType: CoachProposalChangeType = .other,
        beforeJSON: String,
        afterJSON: String,
        label: String,
        accepted: Bool = false,
        decidedAt: Date? = nil
    ) {
        self.id = id
        self.proposalId = proposalId
        self.sortOrder = sortOrder
        self.changeTypeRaw = changeType.rawValue
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
        self.label = label
        self.accepted = accepted
        self.decidedAt = decidedAt
    }

    public var changeType: CoachProposalChangeType {
        get { CoachProposalChangeType(rawValue: changeTypeRaw) ?? .other }
        set { changeTypeRaw = newValue.rawValue }
    }
}

// MARK: - CoachUserReply

@Model
public final class CoachUserReply {
    @Attribute(.unique) public var id: UUID
    public var proposalId: UUID?
    public var createdAt: Date
    public var body: String = "pending"
    public var wasReadByCoach: Bool = false

    public init(
        id: UUID = UUID(),
        proposalId: UUID? = nil,
        createdAt: Date = .now,
        body: String,
        wasReadByCoach: Bool = false
    ) {
        self.id = id
        self.proposalId = proposalId
        self.createdAt = createdAt
        self.body = body
        self.wasReadByCoach = wasReadByCoach
    }
}
