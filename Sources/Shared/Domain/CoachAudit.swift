import Foundation
import SwiftData

public enum CoachRunKind: String, Codable, CaseIterable, Sendable {
    case deterministicRefresh
    case llmAgent
}

public enum CoachRunTrigger: String, Codable, CaseIterable, Sendable {
    case appBootstrap
    case backgroundRefresh
    case healthWeight
    case healthSleep
    case healthActivity
    case weightSaved
    case activeCutChanged
    case macroPlanChanged
    case macroDeviationChanged
    case macroUntrackedChanged
    case voiceCheckIn
    case nostrConversation
    case toolMutationFollowup
    case manual
}

public enum CoachRunStatus: String, Codable, CaseIterable, Sendable {
    case started
    case succeeded
    case failed
    case skipped
    case cancelled
}

public enum CoachNoteSource: String, Codable, CaseIterable, Sendable {
    case user
    case deterministic
    case agent
    case tool
}

public enum CoachNoteKind: String, Codable, CaseIterable, Sendable {
    case checkIn
    case observation
    case planReason
    case foodContext
    case trainingContext
    case sleepContext
    case moodContext
    case digestionContext
    case internalAudit
}

public enum CoachNoteVisibility: String, Codable, CaseIterable, Sendable {
    case userVisible
    case auditOnly
}

public enum CoachToolCallStatus: String, Codable, CaseIterable, Sendable {
    case requested
    case succeeded
    case failed
    case rejected
}

@Model
public final class CoachRun {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var triggerRaw: String
    public var statusRaw: String
    public var cutStartDate: Date?
    public var startedAt: Date
    public var completedAt: Date?
    public var modelID: String?
    public var promptVersion: String?
    public var toolSchemaVersion: String?
    public var contextFingerprint: String
    public var contextSnapshotJSON: Data?
    public var recommendationJSON: Data?
    public var finalResponseJSON: Data?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        kind: CoachRunKind,
        trigger: CoachRunTrigger,
        status: CoachRunStatus = .started,
        cutStartDate: Date?,
        startedAt: Date = .now,
        completedAt: Date? = nil,
        modelID: String? = nil,
        promptVersion: String? = nil,
        toolSchemaVersion: String? = nil,
        contextFingerprint: String,
        contextSnapshotJSON: Data? = nil,
        recommendationJSON: Data? = nil,
        finalResponseJSON: Data? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.triggerRaw = trigger.rawValue
        self.statusRaw = status.rawValue
        self.cutStartDate = cutStartDate.map { Reading.dayStart(of: $0) }
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.modelID = modelID
        self.promptVersion = promptVersion
        self.toolSchemaVersion = toolSchemaVersion
        self.contextFingerprint = contextFingerprint
        self.contextSnapshotJSON = contextSnapshotJSON
        self.recommendationJSON = recommendationJSON
        self.finalResponseJSON = finalResponseJSON
        self.errorMessage = errorMessage
    }

    public var kind: CoachRunKind {
        get { CoachRunKind(rawValue: kindRaw) ?? .deterministicRefresh }
        set { kindRaw = newValue.rawValue }
    }

    public var trigger: CoachRunTrigger {
        get { CoachRunTrigger(rawValue: triggerRaw) ?? .manual }
        set { triggerRaw = newValue.rawValue }
    }

    public var status: CoachRunStatus {
        get { CoachRunStatus(rawValue: statusRaw) ?? .started }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
public final class CoachNote {
    @Attribute(.unique) public var id: UUID
    public var runID: UUID?
    public var sourceRaw: String
    public var kindRaw: String
    public var visibilityRaw: String
    public var cutStartDate: Date?
    public var day: Date?
    public var text: String
    public var payloadJSON: Data?
    public var audioDraftID: UUID?
    public var createdAt: Date
    public var supersededAt: Date?

    public init(
        id: UUID = UUID(),
        runID: UUID? = nil,
        source: CoachNoteSource,
        kind: CoachNoteKind,
        visibility: CoachNoteVisibility = .userVisible,
        cutStartDate: Date?,
        day: Date?,
        text: String,
        payloadJSON: Data? = nil,
        audioDraftID: UUID? = nil,
        createdAt: Date = .now,
        supersededAt: Date? = nil
    ) {
        self.id = id
        self.runID = runID
        self.sourceRaw = source.rawValue
        self.kindRaw = kind.rawValue
        self.visibilityRaw = visibility.rawValue
        self.cutStartDate = cutStartDate.map { Reading.dayStart(of: $0) }
        self.day = day.map { Reading.dayStart(of: $0) }
        self.text = text
        self.payloadJSON = payloadJSON
        self.audioDraftID = audioDraftID
        self.createdAt = createdAt
        self.supersededAt = supersededAt
    }

    public var source: CoachNoteSource {
        get { CoachNoteSource(rawValue: sourceRaw) ?? .user }
        set { sourceRaw = newValue.rawValue }
    }

    public var kind: CoachNoteKind {
        get { CoachNoteKind(rawValue: kindRaw) ?? .observation }
        set { kindRaw = newValue.rawValue }
    }

    public var visibility: CoachNoteVisibility {
        get { CoachNoteVisibility(rawValue: visibilityRaw) ?? .userVisible }
        set { visibilityRaw = newValue.rawValue }
    }
}

@Model
public final class CoachToolCall {
    @Attribute(.unique) public var id: UUID
    public var runID: UUID
    public var providerCallID: String?
    public var sequence: Int
    public var toolName: String
    public var statusRaw: String
    public var requestedAt: Date
    public var completedAt: Date?
    public var argumentsJSON: Data
    public var resultJSON: Data?
    public var errorMessage: String?
    public var targetEntityRaw: String?
    public var targetID: UUID?
    public var beforeJSON: Data?
    public var afterJSON: Data?
    public var idempotencyKey: String

    public init(
        id: UUID = UUID(),
        runID: UUID,
        providerCallID: String? = nil,
        sequence: Int,
        toolName: String,
        status: CoachToolCallStatus = .requested,
        requestedAt: Date = .now,
        completedAt: Date? = nil,
        argumentsJSON: Data,
        resultJSON: Data? = nil,
        errorMessage: String? = nil,
        targetEntityRaw: String? = nil,
        targetID: UUID? = nil,
        beforeJSON: Data? = nil,
        afterJSON: Data? = nil,
        idempotencyKey: String = UUID().uuidString
    ) {
        self.id = id
        self.runID = runID
        self.providerCallID = providerCallID
        self.sequence = sequence
        self.toolName = toolName
        self.statusRaw = status.rawValue
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.argumentsJSON = argumentsJSON
        self.resultJSON = resultJSON
        self.errorMessage = errorMessage
        self.targetEntityRaw = targetEntityRaw
        self.targetID = targetID
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
        self.idempotencyKey = idempotencyKey
    }

    public var status: CoachToolCallStatus {
        get { CoachToolCallStatus(rawValue: statusRaw) ?? .requested }
        set { statusRaw = newValue.rawValue }
    }
}
