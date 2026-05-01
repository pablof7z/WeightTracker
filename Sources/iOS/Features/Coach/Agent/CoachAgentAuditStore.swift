import Foundation

enum CoachAgentRunTrigger: String, Codable, CaseIterable, Sendable {
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

enum CoachAgentRunAuditStatus: String, Codable, Sendable {
    case started
    case succeeded
    case failed
    case cancelled
}

enum CoachAgentToolAuditStatus: String, Codable, Sendable {
    case succeeded
    case failed
    case rejected
}

struct CoachAgentRunAuditRecord: Codable, Equatable, Sendable {
    var trigger: CoachAgentRunTrigger
    var status: CoachAgentRunAuditStatus
    var cutStartDate: Date?
    var startedAt: Date
    var modelID: String
    var promptVersion: String
    var toolSchemaVersion: String
    var contextFingerprint: String
    var contextSnapshotJSON: Data?
}

struct CoachAgentRunCompletionAuditRecord: Codable, Equatable, Sendable {
    var runID: UUID
    var status: CoachAgentRunAuditStatus
    var completedAt: Date
    var finalResponseJSON: Data?
    var errorMessage: String?
}

struct CoachAgentNoteAuditRecord: Codable, Equatable, Sendable {
    var runID: UUID
    var source: String
    var kind: String
    var visibility: String
    var cutStartDate: Date?
    var day: Date?
    var text: String
    var payloadJSON: Data?
    var audioDraftID: UUID?
    var createdAt: Date
}

struct CoachAgentToolCallAuditRecord: Codable, Equatable, Sendable {
    var runID: UUID
    var providerCallID: String?
    var sequence: Int
    var toolName: String
    var status: CoachAgentToolAuditStatus
    var requestedAt: Date
    var completedAt: Date
    var argumentsJSON: Data
    var resultJSON: Data?
    var errorMessage: String?
    var targetEntity: String?
    var targetID: UUID?
    var beforeJSON: Data?
    var afterJSON: Data?
    var idempotencyKey: String
}

@MainActor
protocol CoachAgentAuditStore: AnyObject {
    @discardableResult
    func beginRun(_ record: CoachAgentRunAuditRecord) async throws -> UUID

    func finishRun(_ record: CoachAgentRunCompletionAuditRecord) async throws

    @discardableResult
    func appendCoachNote(_ record: CoachAgentNoteAuditRecord) async throws -> UUID

    func recordToolCall(_ record: CoachAgentToolCallAuditRecord) async throws
}

enum CoachAgentAuditAdapterError: LocalizedError {
    case unknownRun(UUID)
    case noteRejected

    var errorDescription: String? {
        switch self {
        case .unknownRun(let id):
            return "Coach audit run \(id) was not found."
        case .noteRejected:
            return "Coach audit store rejected the note."
        }
    }
}

extension CoachAuditStore: CoachAgentAuditStore {
    func beginRun(_ record: CoachAgentRunAuditRecord) async throws -> UUID {
        let run = beginRun(
            kind: .llmAgent,
            trigger: CoachRunTrigger(rawValue: record.trigger.rawValue) ?? .manual,
            cutStartDate: record.cutStartDate,
            contextFingerprint: record.contextFingerprint,
            contextSnapshotJSON: record.contextSnapshotJSON,
            modelID: record.modelID,
            promptVersion: record.promptVersion,
            toolSchemaVersion: record.toolSchemaVersion,
            now: record.startedAt
        )
        return run.id
    }

    func finishRun(_ record: CoachAgentRunCompletionAuditRecord) async throws {
        guard let run = recentRuns(limit: Int.max).first(where: { $0.id == record.runID }) else {
            throw CoachAgentAuditAdapterError.unknownRun(record.runID)
        }

        switch record.status {
        case .succeeded:
            completeRun(
                run,
                recommendationJSON: nil,
                finalResponseJSON: record.finalResponseJSON,
                now: record.completedAt
            )
        case .failed, .cancelled:
            failRun(
                run,
                errorMessage: record.errorMessage ?? record.status.rawValue,
                now: record.completedAt
            )
        case .started:
            break
        }
    }

    func appendCoachNote(_ record: CoachAgentNoteAuditRecord) async throws -> UUID {
        guard let note = appendNote(
            source: CoachNoteSource(rawValue: record.source) ?? .agent,
            kind: CoachNoteKind(rawValue: record.kind) ?? .observation,
            visibility: CoachNoteVisibility(rawValue: record.visibility) ?? .userVisible,
            cutStartDate: record.cutStartDate,
            day: record.day,
            text: record.text,
            payloadJSON: record.payloadJSON,
            audioDraftID: record.audioDraftID,
            runID: record.runID,
            createdAt: record.createdAt
        ) else {
            throw CoachAgentAuditAdapterError.noteRejected
        }
        return note.id
    }

    func recordToolCall(_ record: CoachAgentToolCallAuditRecord) async throws {
        let call = beginToolCall(
            runID: record.runID,
            providerCallID: record.providerCallID,
            sequence: record.sequence,
            toolName: record.toolName,
            argumentsJSON: record.argumentsJSON,
            idempotencyKey: record.idempotencyKey,
            now: record.requestedAt
        )

        switch record.status {
        case .succeeded:
            completeToolCall(
                call,
                resultJSON: record.resultJSON,
                targetEntityRaw: record.targetEntity,
                targetID: record.targetID,
                beforeJSON: record.beforeJSON,
                afterJSON: record.afterJSON,
                now: record.completedAt
            )
        case .failed:
            failToolCall(
                call,
                errorMessage: record.errorMessage ?? record.status.rawValue,
                now: record.completedAt
            )
        case .rejected:
            rejectToolCall(
                call,
                errorMessage: record.errorMessage ?? record.status.rawValue,
                now: record.completedAt
            )
        }
    }
}
