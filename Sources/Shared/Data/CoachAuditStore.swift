import Foundation
import SwiftData

@MainActor
public final class CoachAuditStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func recentRuns(limit: Int = 50) -> [CoachRun] {
        var descriptor = FetchDescriptor<CoachRun>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    public func recentNotes(limit: Int = 50, userVisibleOnly: Bool = false) -> [CoachNote] {
        let descriptor: FetchDescriptor<CoachNote>
        if userVisibleOnly {
            let visibility = CoachNoteVisibility.userVisible.rawValue
            descriptor = FetchDescriptor<CoachNote>(
                predicate: #Predicate<CoachNote> { $0.visibilityRaw == visibility },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<CoachNote>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        }
        return Array(((try? context.fetch(descriptor)) ?? []).prefix(limit))
    }

    public func notes(runID: UUID) -> [CoachNote] {
        let descriptor = FetchDescriptor<CoachNote>(
            predicate: #Predicate<CoachNote> { $0.runID == runID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func toolCalls(runID: UUID) -> [CoachToolCall] {
        let descriptor = FetchDescriptor<CoachToolCall>(
            predicate: #Predicate<CoachToolCall> { $0.runID == runID },
            sortBy: [SortDescriptor(\.sequence, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    public func beginRun(
        kind: CoachRunKind,
        trigger: CoachRunTrigger,
        cutStartDate: Date?,
        contextFingerprint: String,
        contextSnapshotJSON: Data?,
        userInputText: String? = nil,
        modelID: String? = nil,
        promptVersion: String? = nil,
        toolSchemaVersion: String? = nil,
        now: Date = .now
    ) -> CoachRun {
        let run = CoachRun(
            kind: kind,
            trigger: trigger,
            cutStartDate: cutStartDate,
            startedAt: now,
            modelID: modelID,
            promptVersion: promptVersion,
            toolSchemaVersion: toolSchemaVersion,
            contextFingerprint: contextFingerprint,
            contextSnapshotJSON: contextSnapshotJSON,
            userInputText: userInputText
        )
        context.insert(run)
        save()
        return run
    }

    public func completeRun(
        _ run: CoachRun,
        recommendationJSON: Data?,
        finalResponseJSON: Data? = nil,
        now: Date = .now
    ) {
        run.status = .succeeded
        run.completedAt = now
        run.recommendationJSON = recommendationJSON
        run.finalResponseJSON = finalResponseJSON
        run.errorMessage = nil
        save()
    }

    public func failRun(_ run: CoachRun, errorMessage: String, now: Date = .now) {
        run.status = .failed
        run.completedAt = now
        run.errorMessage = errorMessage
        save()
    }

    @discardableResult
    public func appendNote(
        source: CoachNoteSource,
        kind: CoachNoteKind,
        visibility: CoachNoteVisibility = .userVisible,
        cutStartDate: Date?,
        day: Date?,
        text: String,
        payloadJSON: Data? = nil,
        audioDraftID: UUID? = nil,
        runID: UUID? = nil,
        createdAt: Date = .now
    ) -> CoachNote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let note = CoachNote(
            runID: runID,
            source: source,
            kind: kind,
            visibility: visibility,
            cutStartDate: cutStartDate,
            day: day,
            text: trimmed,
            payloadJSON: payloadJSON,
            audioDraftID: audioDraftID,
            createdAt: createdAt
        )
        context.insert(note)
        save()
        return note
    }

    @discardableResult
    public func beginToolCall(
        runID: UUID,
        providerCallID: String?,
        sequence: Int,
        toolName: String,
        argumentsJSON: Data,
        idempotencyKey: String,
        now: Date = .now
    ) -> CoachToolCall {
        let call = CoachToolCall(
            runID: runID,
            providerCallID: providerCallID,
            sequence: sequence,
            toolName: toolName,
            requestedAt: now,
            argumentsJSON: argumentsJSON,
            idempotencyKey: idempotencyKey
        )
        context.insert(call)
        save()
        return call
    }

    public func completeToolCall(
        _ call: CoachToolCall,
        resultJSON: Data?,
        targetEntityRaw: String? = nil,
        targetID: UUID? = nil,
        beforeJSON: Data? = nil,
        afterJSON: Data? = nil,
        now: Date = .now
    ) {
        call.status = .succeeded
        call.completedAt = now
        call.resultJSON = resultJSON
        call.targetEntityRaw = targetEntityRaw
        call.targetID = targetID
        call.beforeJSON = beforeJSON
        call.afterJSON = afterJSON
        call.errorMessage = nil
        save()
    }

    public func failToolCall(_ call: CoachToolCall, errorMessage: String, now: Date = .now) {
        call.status = .failed
        call.completedAt = now
        call.errorMessage = errorMessage
        save()
    }

    public func rejectToolCall(_ call: CoachToolCall, errorMessage: String, now: Date = .now) {
        call.status = .rejected
        call.completedAt = now
        call.errorMessage = errorMessage
        save()
    }

    public func deleteAll() {
        for run in recentRuns(limit: Int.max) {
            context.delete(run)
        }
        for note in recentNotes(limit: Int.max) {
            context.delete(note)
        }
        let toolDescriptor = FetchDescriptor<CoachToolCall>()
        for call in (try? context.fetch(toolDescriptor)) ?? [] {
            context.delete(call)
        }
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("[CoachAuditStore] save failed: \(error)")
        }
    }
}
