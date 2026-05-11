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
        mealScheduleStore: MealScheduleStore,
        mealEventStore: MealEventStore,
        auditStore: CoachAgentAuditStore,
        mealCalculator: MealCalculator? = nil,
        scheduledNudgeStore: ScheduledNudgeStore? = nil,
        client: CoachOpenRouterClient = CoachOpenRouterClient(),
        model: String = AppConstants.defaultOpenRouterModel,
        maxTurns: Int = 8,
        activeCutProvider: @escaping () -> ActiveCut? = { ActiveCutStore.load() },
        onMutation: (() -> Void)? = nil,
        recordMemory: ((String) throws -> CoachAgentMemory)? = nil,
        pinTodayNote: ((String) -> Void)? = nil
    ) {
        self.client = client
        self.auditStore = auditStore
        self.model = model
        self.maxTurns = maxTurns
        // Default the calculator to one backed by the same OpenRouter
        // credential pool used by the outer agent. Tests inject their own.
        let calculator = mealCalculator ?? MealCalculator(openRouterClient: client)
        self.dispatcher = CoachAgentToolDispatcher(
            repository: repository,
            macroPlanStore: macroPlanStore,
            macroDeviationStore: macroDeviationStore,
            macroUntrackedRangeStore: macroUntrackedRangeStore,
            mealScheduleStore: mealScheduleStore,
            mealEventStore: mealEventStore,
            auditStore: auditStore,
            mealCalculator: calculator,
            scheduledNudgeStore: scheduledNudgeStore,
            activeCutProvider: activeCutProvider,
            onMutation: onMutation,
            recordMemory: recordMemory,
            pinTodayNote: pinTodayNote
        )
    }

    func run(
        transcript: String,
        trigger: CoachAgentRunTrigger = .manual,
        historyDays: Int = 21
    ) async {
        UserDefaults.standard.set(Date(), forKey: "coach.lastRunAt")
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

        let cutStartDate = snapshot.activeCut?.startDate

        let runID: UUID
        do {
            runID = try await auditStore.beginRun(CoachAgentRunAuditRecord(
                trigger: trigger,
                status: .started,
                cutStartDate: cutStartDate,
                startedAt: startedAt,
                modelID: model,
                promptVersion: CoachAgentPrompt.version,
                toolSchemaVersion: CoachTool.schemaVersion,
                contextFingerprint: Self.fingerprint(snapshotJSON),
                contextSnapshotJSON: snapshotJSON,
                userInputText: trimmed
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
                    finalResponseJSON: response.assistantMessageJSON,
                    cutStartDate: cutStartDate
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
            finalResponseJSON: lastAssistantJSON,
            cutStartDate: cutStartDate
        )
    }

    // MARK: - Conversation mode

    /// Build the initial messages array (system prompt only) for a fresh
    /// back-and-forth conversation. Each turn appends a user message and the
    /// assistant + tool messages produced by `runTurn`.
    func buildInitialMessages(snapshotHistoryDays: Int = 21) -> [[String: Any]] {
        let snapshot = dispatcher.makeSnapshot(historyDays: snapshotHistoryDays)
        let snapshotJSON: Data
        do {
            snapshotJSON = try Self.encoder.encode(snapshot)
        } catch {
            snapshotJSON = Data("{}".utf8)
        }
        return [
            [
                "role": "system",
                "content": CoachAgentPrompt.systemMessage(
                    snapshotJSON: snapshotJSON,
                    agentDefinition: CoachNostrAgentSettings.load().systemPrompt,
                    memories: CoachNostrAgentState.load().memories
                )
            ]
        ]
    }

    /// Execute a single conversation turn against OpenRouter while keeping the
    /// existing conversation history intact. Returns the updated message list
    /// (including the assistant reply and any tool messages) plus the final
    /// assistant text — ready for TTS playback.
    ///
    /// When `imageAttached` is true we override the configured model with the
    /// vision-capable default so that multimodal user messages are accepted.
    func runTurn(
        messages inputMessages: [[String: Any]],
        userMessage: [String: Any],
        imageAttached: Bool
    ) async -> (messages: [[String: Any]], finalText: String?) {
        var messages = inputMessages
        messages.append(userMessage)

        let startedAt = Date()
        let visionModel = UserDefaults.standard.string(forKey: AppPrefKey.coachVisionModel)
            ?? AppConstants.defaultCoachVisionModel
        let modelOverride = imageAttached ? visionModel : model

        let contextData = (try? JSONSerialization.data(withJSONObject: messages)) ?? Data()
        let contextFingerprint = Self.fingerprint(contextData)
        let cutStartDate = ActiveCutStore.load()?.startDate

        let userInputText: String?
        if let text = userMessage["content"] as? String {
            userInputText = text
        } else if let parts = userMessage["content"] as? [[String: Any]],
                  let textPart = parts.first(where: { $0["type"] as? String == "text" }),
                  let text = textPart["text"] as? String {
            userInputText = text
        } else {
            userInputText = nil
        }

        let runID = (try? await auditStore.beginRun(CoachAgentRunAuditRecord(
            trigger: .conversation,
            status: .started,
            cutStartDate: cutStartDate,
            startedAt: startedAt,
            modelID: modelOverride,
            promptVersion: CoachAgentPrompt.version,
            toolSchemaVersion: CoachTool.schemaVersion,
            contextFingerprint: contextFingerprint,
            contextSnapshotJSON: nil,
            userInputText: userInputText
        ))) ?? UUID()

        var lastText: String?
        var toolCallCount = 0

        for _ in 0..<maxTurns {
            let response: CoachToolCallResponse
            do {
                response = try await client.chatToolCalling(
                    messages: messages,
                    tools: CoachTool.json,
                    model: modelOverride,
                    feature: "coach.conversation.turn"
                )
            } catch {
                try? await auditStore.finishRun(CoachAgentRunCompletionAuditRecord(
                    runID: runID,
                    status: .failed,
                    completedAt: Date(),
                    finalResponseJSON: nil,
                    errorMessage: error.localizedDescription
                ))
                return (messages, nil)
            }

            guard let assistant = try? JSONSerialization.jsonObject(with: response.assistantMessageJSON) as? [String: Any] else {
                try? await auditStore.finishRun(CoachAgentRunCompletionAuditRecord(
                    runID: runID,
                    status: .failed,
                    completedAt: Date(),
                    finalResponseJSON: nil,
                    errorMessage: "Assistant message was not a JSON object"
                ))
                return (messages, nil)
            }
            messages.append(assistant)

            if response.toolCalls.isEmpty {
                lastText = assistant["content"] as? String
                try? await auditStore.finishRun(CoachAgentRunCompletionAuditRecord(
                    runID: runID,
                    status: .succeeded,
                    completedAt: Date(),
                    finalResponseJSON: response.assistantMessageJSON,
                    errorMessage: nil
                ))
                return (messages, lastText)
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
                } catch let dispatchError as CoachToolDispatchError {
                    resultData = encodeError(dispatchError.message)
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

        try? await auditStore.finishRun(CoachAgentRunCompletionAuditRecord(
            runID: runID,
            status: .succeeded,
            completedAt: Date(),
            finalResponseJSON: nil,
            errorMessage: "tool turn cap reached"
        ))
        return (messages, lastText)
    }

    private func finishSucceeded(
        runID: UUID,
        toolCallCount: Int,
        turnsExhausted: Bool,
        finalResponseJSON: Data?,
        cutStartDate: Date?
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

        // Persist the coach's final reply as an audit-only note.
        // Replies are surfaced via the thread view where they are appended
        // explicitly; we do NOT auto-pin them to the Today view.
        if let data = finalResponseJSON,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["content"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? await auditStore.appendCoachNote(CoachAgentNoteAuditRecord(
                runID: runID,
                source: "agent",
                kind: "observation",
                visibility: "auditOnly",
                cutStartDate: cutStartDate,
                day: nil,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                payloadJSON: nil,
                audioDraftID: nil,
                createdAt: Date()
            ))
        }

        NotificationCenter.default.post(name: .coachProposalDidChange, object: nil)

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
        // Use local-timezone ISO8601 so day-keyed dates (stored as local
        // midnight) round-trip to the same calendar day the user sees. The
        // default `.iso8601` emits UTC, which for users east of UTC shifts
        // dates back a day and causes the coach to mis-attribute step counts
        // (e.g. reporting today's partial steps as "yesterday").
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(CoachDateEncoding.iso8601Local.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

enum CoachDateEncoding {
    static let iso8601Local: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()
}

private enum CoachAgentPrompt {
    static let version = "coach-agent-v7"

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
        You are the WeightTracker coach — a contracted nutritional professional managing an active weight cut. You are not a chatbot or a wellness assistant. You are a professional who owns the plan, notices patterns, and proposes specific changes.
        \(definitionBlock)
        \(memoriesBlock)

        ## Your job

        Read the data in the snapshot. Notice what is worth noticing. Draw your own conclusions from the evidence — do not apply a checklist, do not label things before you have looked. The user's situation is always specific; your response should be specific to it.

        What to look for (not an ordered checklist — consider all of these as you read the data):
        - Weight trend over 7–14 days. Is it moving? At what rate? Does it match the plan?
        - Macro adherence. Is it consistent? Which macro drifts most? Is adherence clear or ambiguous?
        - Meal timing and skip patterns. Is there a slot the user consistently misses or delays? What does hunger-after look like?
        - Activity. Are steps trending up or down relative to the user's target? Has there been a meaningful change in exercise minutes?
        - Sleep. Is it above or below 7h? Has it changed recently?
        - Untracked ranges. Do gaps in the data explain anything that might otherwise look like non-adherence?
        - Coach notes. What has already been tried? What did the user push back on? What was the rationale for the last plan change?
        - Memories. What does the user want you to remember about their constraints, preferences, and lifestyle?

        The answer to "what is going on" emerges from reading these together, not from any one signal.

        ## Communication style

        Direct, second-person, present tense. Every sentence references a number, a date, or a behavior. Silence when there is nothing specific to say. Prescriptive, not Socratic — propose a change, state the reason, ask for confirmation. Never encourage, never moralize.

        NEVER say: "as an AI", "great job", "you're doing amazing", "trust the process", "maybe try", "you could consider", "I noticed something interesting." No hedging. No motivation filler. If you have nothing concrete, say nothing.

        ## Intervention toolkit (coach knowledge — apply when the situation calls for it)

        These are interventions you know about. Use them when the evidence supports it, not on a fixed schedule.

        **Macro adjustments:** typically 50–150 kcal/day. Prefer reducing carbs first. Never create impossible macros (protein + fat > kcal). Keep protein ≥1.0 g/kg bodyweight. Keep fat ≥0.3 g/lb. Minimums: 1200 kcal (women), 1500 kcal (men).

        **Meal timing shifts:** Earlier eating window is generally better. Protein distribution: 3–4 doses of 30–40g, 3–5 hours apart. Largest meal earlier in the day. Last meal ≥3h before bed.

        **Activity targets:** Steps are the cheapest lever — no muscle-loss penalty. When the user is consistently below target, offer two options: hit the target, or compensate with a small kcal cut. Never just nag.

        **Diet breaks and refeeds:** After prolonged deficit (typically 6–8 weeks) or when lean mass loss is a concern, a break at maintenance for 7–14 days restores leptin and improves adherence. A single-day refeed is a lighter intervention. Use `schedule_diet_break` and `schedule_refeed` tools.

        **What to check before any kcal cut:** Is adherence actually good? Is sleep normal? Is activity stable? Are there untracked days that explain the flat trend? Fix execution problems before cutting food.

        ## Concrete food

        When you propose a meal or slot, you must call `propose_meal_plan` first to get actual food items with grams. Do not present abstract macro numbers without food. Round displayed values: P/F/C to nearest 5g, kcal to nearest 50.

        When the user describes food, call `calculate_meal`. One call per meal. After calculating, present the result before logging or persisting anything.

        ## Proactive nudges

        You can schedule notifications via `schedule_nudge` — use this during check-ins to set up time-delayed reminders. Each nudge must be actionable in under 30 seconds. Maximum 2 per session. Write nudge text in first-person from the user's perspective: "Log lunch now or mark it skipped." The nudge fires without user action; it should not require context.

        ## Tool policy

        - Read before mutating when state is ambiguous.
        - Safe mutation tools: `append_coach_note`, `record_memory`, `replace_current_macro_plan`, `log_macro_deviation`, `mark_untracked_range`, `replace_current_meal_schedule`, `log_meal_event`, `set_step_target`, `schedule_nudge`, `cancel_nudge`, `schedule_diet_break`, `schedule_refeed`, `pin_today_note`.
        - Pure-compute tools (no side effects): `calculate_meal`, `propose_meal_plan`.
        - Two-turn rule: for meal schedule changes and kcal changes, propose in natural language first. Execute the mutation only after the user explicitly accepts. Never rewrite a plan on a single ambiguous message.
        - Use `record_memory` only for stable facts: food dislikes, dietary constraints, lifestyle patterns, long-arc goals. Precede every `record_memory` call with "I am going to remember that you …" in your reply.
        - Use `append_coach_note` for all interventions, plan reasons, and user pushback. This is the audit trail.
        - Use `pin_today_note` at most once per session, only when you have a specific, actionable focus for the day — e.g. after a weigh-in that reveals a clear trend, or after the user asks for a daily focus. Never pin generic motivational text.

        Current data snapshot:
        \(snapshot)
        """
    }
}
