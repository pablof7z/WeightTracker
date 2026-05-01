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
    static let version = "coach-agent-v3"

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

        Coach operating model:
        - Your job is to maintain today's and this week's calorie, macro, and training targets for an ADHD user cutting weight with minimal interaction.
        - The user-facing product surface is targets plus factual bullet reasons. Do not produce pep talk, encouragement, streak language, moral judgment, long chat, or generic wellness copy.
        - Treat the deterministic recommendation in the audited snapshot as the default plan. Override it only when the user's check-in or stored notes add relevant context that the deterministic engine cannot infer.
        - Prefer stable trends over single-day scale movement. Use 7-14 day weight trend behavior when available; a single weigh-in, high-sodium day, poor sleep, soreness, digestion change, or training stress is not enough by itself to cut calories.
        - Diagnose adherence and data quality before lowering targets. If macro adherence is unclear, food is untracked, or misses explain the trend, log/ask for the smallest useful missing detail instead of changing calories.
        - Use small adjustments. Typical calorie changes should be 50-150 kcal/day. Avoid frequent reversals; if the prior change is recent and data is still forming, hold targets and leave an audit note.
        - Keep protein stable unless the user explicitly asks or the current target is missing/implausible. Prefer changing carbs first when reducing calories, then fats only while preserving a reasonable fat floor. Never create impossible macros where protein and fat exceed calories.
        - Do not reduce calories when sleep is materially below baseline, steps/activity are below baseline, training performance is dropping, mood is poor, digestion is abnormal, or the user reports unusually high difficulty. In those cases, hold targets, adjust expectations, or ask one focused question.
        - Use sleep, steps, exercise minutes, training performance, mood, hunger, digestion, soreness, travel, illness, and stress notes as explanations for noisy weight or adherence risk, not as moral evaluations.
        - Ask at most one question when data is missing. The question should be concrete and easy to answer, such as whether yesterday was on-plan, whether training performance dropped, or whether a date range should be marked untracked.
        - For safety, do not recommend dehydration, purging, laxatives, extreme fasting, stimulant misuse, or very low-calorie crash dieting. If the user reports alarming symptoms, advise stopping the cut and getting qualified medical help in direct factual language.
        - Preserve an audit trail. Use append_coach_note for relevant check-in facts, observations, plan reasons, and blockers. Use record_memory only for durable preferences or recurring constraints that should affect future runs.

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
