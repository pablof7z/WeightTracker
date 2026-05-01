import Combine
import CryptoKit
import Foundation

@MainActor
final class CoachAgentSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running(turn: Int)
        case completed(runID: UUID, toolCallCount: Int, turnsExhausted: Bool)
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastRunID: UUID?
    @Published private(set) var lastFinalAssistantText: String?

    let client: CoachOpenRouterClient
    let dispatcher: CoachAgentToolDispatcher
    let auditStore: CoachAgentAuditStore
    let model: String
    let maxTurns: Int

    init(
        repository: ReadingRepository,
        macroPlanStore: MacroPlanStore,
        macroDeviationStore: MacroDeviationStore,
        macroUntrackedRangeStore: MacroUntrackedRangeStore,
        auditStore: CoachAgentAuditStore,
        client: CoachOpenRouterClient = CoachOpenRouterClient(),
        model: String = AppConstants.defaultOpenRouterModel,
        maxTurns: Int = 8,
        activeCutProvider: @escaping () -> ActiveCut? = { ActiveCutStore.load() },
        onMutation: (() -> Void)? = nil,
        recordMemory: ((String) throws -> CoachAgentMemory)? = nil
    ) {
        self.client = client
        self.auditStore = auditStore
        self.model = model
        self.maxTurns = maxTurns
        self.dispatcher = CoachAgentToolDispatcher(
            repository: repository,
            macroPlanStore: macroPlanStore,
            macroDeviationStore: macroDeviationStore,
            macroUntrackedRangeStore: macroUntrackedRangeStore,
            auditStore: auditStore,
            activeCutProvider: activeCutProvider,
            onMutation: onMutation,
            recordMemory: recordMemory
        )
    }

    func run(
        transcript: String,
        trigger: CoachAgentRunTrigger = .manual,
        historyDays: Int = 21
    ) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .failed(message: "No coach transcript provided")
            return
        }

        let startedAt = Date()
        let snapshot = dispatcher.makeSnapshot(historyDays: historyDays)

        let snapshotJSON: Data
        do {
            snapshotJSON = try Self.encoder.encode(snapshot)
        } catch {
            phase = .failed(message: "Could not encode coach context: \(error.localizedDescription)")
            return
        }

        let runID: UUID
        do {
            runID = try await auditStore.beginRun(CoachAgentRunAuditRecord(
                trigger: trigger,
                status: .started,
                cutStartDate: snapshot.activeCut?.startDate,
                startedAt: startedAt,
                modelID: model,
                promptVersion: CoachAgentPrompt.version,
                toolSchemaVersion: CoachTool.schemaVersion,
                contextFingerprint: Self.fingerprint(snapshotJSON),
                contextSnapshotJSON: snapshotJSON
            ))
        } catch {
            phase = .failed(message: "Could not start coach audit run: \(error.localizedDescription)")
            return
        }

        var messages: [[String: Any]] = [
            [
                "role": "system",
                "content": CoachAgentPrompt.systemMessage(
                    snapshotJSON: snapshotJSON,
                    agentDefinition: CoachNostrAgentSettings.load().systemPrompt,
                    memories: CoachNostrAgentState.load().memories
                )
            ],
            ["role": "user", "content": trimmed]
        ]
        var toolCallCount = 0
        var lastAssistantJSON: Data?

        phase = .running(turn: 0)

        for turn in 0..<maxTurns {
            phase = .running(turn: turn)

            let response: CoachToolCallResponse
            do {
                let openRouterClient = client
                response = try await openRouterClient.chatToolCalling(
                    messages: messages,
                    tools: CoachTool.json,
                    model: model,
                    feature: "coach.agent.run"
                )
            } catch {
                await finishFailed(runID: runID, message: "OpenRouter call failed: \(error.localizedDescription)")
                return
            }

            lastAssistantJSON = response.assistantMessageJSON
            do {
                guard let assistant = try JSONSerialization.jsonObject(with: response.assistantMessageJSON) as? [String: Any] else {
                    await finishFailed(runID: runID, message: "Assistant message was not a JSON object")
                    return
                }
                messages.append(assistant)
            } catch {
                await finishFailed(runID: runID, message: "Could not decode assistant message: \(error.localizedDescription)")
                return
            }

            if response.toolCalls.isEmpty {
                captureFinalAssistantText(from: response.assistantMessageJSON)
                await finishSucceeded(
                    runID: runID,
                    toolCallCount: toolCallCount,
                    turnsExhausted: false,
                    finalResponseJSON: response.assistantMessageJSON
                )
                return
            }

            for toolCall in response.toolCalls {
                toolCallCount += 1
                let resultData: Data
                do {
                    resultData = try await dispatcher.dispatch(
                        name: toolCall.name,
                        argsJSON: toolCall.arguments,
                        runID: runID,
                        providerCallID: toolCall.id,
                        sequence: toolCallCount
                    )
                } catch let error as CoachToolDispatchError {
                    resultData = encodeError(error.message)
                } catch {
                    resultData = encodeError(error.localizedDescription)
                }

                messages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": String(data: resultData, encoding: .utf8) ?? "{}"
                ])
            }
        }

        await finishSucceeded(
            runID: runID,
            toolCallCount: toolCallCount,
            turnsExhausted: true,
            finalResponseJSON: lastAssistantJSON
        )
    }

    private func finishSucceeded(
        runID: UUID,
        toolCallCount: Int,
        turnsExhausted: Bool,
        finalResponseJSON: Data?
    ) async {
        do {
            try await auditStore.finishRun(CoachAgentRunCompletionAuditRecord(
                runID: runID,
                status: .succeeded,
                completedAt: Date(),
                finalResponseJSON: finalResponseJSON,
                errorMessage: turnsExhausted ? "tool turn cap reached" : nil
            ))
        } catch {
            phase = .failed(message: "Could not finish coach audit run: \(error.localizedDescription)")
            return
        }

        lastRunID = runID
        phase = .completed(
            runID: runID,
            toolCallCount: toolCallCount,
            turnsExhausted: turnsExhausted
        )
    }

    private func finishFailed(runID: UUID, message: String) async {
        try? await auditStore.finishRun(CoachAgentRunCompletionAuditRecord(
            runID: runID,
            status: .failed,
            completedAt: Date(),
            finalResponseJSON: nil,
            errorMessage: message
        ))
        lastRunID = runID
        phase = .failed(message: message)
    }

    private func captureFinalAssistantText(from data: Data) {
        guard
            let assistant = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = assistant["content"] as? String
        else {
            lastFinalAssistantText = nil
            return
        }
        lastFinalAssistantText = text
    }

    private func encodeError(_ message: String) -> Data {
        let payload = ["error": message]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            ?? Data("{\"error\":\"unknown\"}".utf8)
    }

    private static func fingerprint(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private enum CoachAgentPrompt {
    static let version = "coach-agent-v2"

    static func systemMessage(
        snapshotJSON: Data,
        agentDefinition: String = CoachNostrAgentSettings.defaultSystemPrompt,
        memories: [CoachAgentMemory] = []
    ) -> String {
        let snapshot = String(data: snapshotJSON, encoding: .utf8) ?? "{}"
        let trimmedDefinition = agentDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        let definitionBlock = trimmedDefinition.isEmpty ? "" : """

        Agent definition:
        \(trimmedDefinition)
        """
        let memoryLines = memories.prefix(12).map { "- \($0.text)" }.joined(separator: "\n")
        let memoriesBlock = memoryLines.isEmpty ? "" : """

        Agent memories:
        \(memoryLines)
        """
        return """
        You are the WeightTracker coach agent runtime for a deliberate weight cut.
        \(definitionBlock)
        \(memoriesBlock)

        Tool policy:
        - Prefer read tools before mutations when the current state is ambiguous.
        - Only mutate through these safe tools: append_coach_note, record_memory, replace_current_macro_plan, log_macro_deviation, mark_untracked_range.
        - Use record_memory only for stable facts that should affect future coach conversations.
        - Do not invent readings, sleep, activity, food logs, or macro adherence.
        - There is no persist_coach_run tool. Run, note, and tool-call persistence is handled by the host audit store.
        - If a mutation is rejected, use the tool error to self-correct once or explain the blocker.

        Current audited context snapshot:
        \(snapshot)
        """
    }
}
