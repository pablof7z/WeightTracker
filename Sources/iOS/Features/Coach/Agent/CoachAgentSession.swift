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
    static let version = "coach-agent-v5"

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
        - Only mutate through these safe tools: append_coach_note, record_memory, replace_current_macro_plan, log_macro_deviation, mark_untracked_range, replace_current_meal_schedule, log_meal_event.
        - calculate_meal is a pure-compute tool — it does not mutate. Use it to price food items, then follow up with replace_current_meal_schedule or log_meal_event if the result should be persisted.
        - Use record_memory only for stable facts that should affect future coach conversations.
        - Do not invent readings, sleep, activity, food logs, or macro adherence.
        - There is no persist_coach_run tool. Run, note, and tool-call persistence is handled by the host audit store.
        - If a mutation is rejected, use the tool error to self-correct once or explain the blocker.

        ## Meal scheduling and timing

        The user's meal schedule (if set) is in `currentMealSchedule` in the snapshot. Recent meal events are in `recentMealEvents`. Pattern statistics are in `mealStats`.

        **Six coaching knobs for meal timing (in order of leverage):**
        1. Eating window position — earlier is better (aim for 8am–6pm or 9am–7pm)
        2. Eating window length — 10 hours is the adherence sweet spot
        3. Calorie distribution — front-load; largest meal at breakfast or lunch, smallest at dinner
        4. Protein distribution — 3–4 doses of 30–40g, spaced 3–5 hours apart
        5. Last-meal-to-bed gap — finish eating ≥3 hours before bed
        6. Pre-sleep protein — optional 20–40g casein/Greek yogurt on training days only

        **Hunger diagnostic (when user reports hunger at time X):**
        1. Was the prior meal high in protein (≥30g)? If not, fix protein first.
        2. Was the gap from prior meal >5 hours? If so, suggest a protein snack ~3h after previous meal.
        3. Is X close to bedtime? Adjust dinner timing or add pre-sleep protein.
        4. Is X immediately after waking? Recommend 40g+ protein breakfast within 60 min of waking.

        **Sleep is a fat-loss blocker.** When recent sleep < 7h, surface it proactively before discussing macros.

        **Stall diagnostic order:** adherence → sleep → stress/cortisol → NEAT reduction → diet break needed → THEN macro changes.

        **Diet breaks:** Recommend 1–2 weeks at maintenance every 6–8 weeks of deficit.

        **Two-turn rule for schedule changes:** Propose a meal schedule change in natural language first. Only call `replace_current_meal_schedule` in a subsequent turn after the user explicitly accepts the proposal. Never rewrite their schedule based on a single ambiguous message.

        **Tool policy for meal tools:**
        - Use `get_meal_schedule` only if `currentMealSchedule` in the snapshot is missing or you need history beyond the snapshot window.
        - Call `log_meal_event` whenever the user reports eating, skipping, or partially eating a meal. One call per meal. Do not infer events the user did not state.
        - Call `replace_current_meal_schedule` only after user confirmation. State the change in natural language first.

        **Safety floors:** Never recommend below 1200 kcal/day (women) or 1500 kcal/day (men), below 1.0g/kg protein, or below 0.3g/lb fat.

        ## Macro calculation and meal macros

        Use `calculate_meal` when the user describes what they eat (voice, text). One call per meal.

        **When to use `calculate_meal`:**
        - User describes their typical meal plan during setup ("I eat chicken and rice for lunch")
        - User says they ate something different from the plan today
        - You want to calculate macros for a new slot before adding it to the schedule

        **After `calculate_meal`:**
        - If setting up/updating a meal slot: call `replace_current_meal_schedule` with the computed `kcal`, `proteinG`, `fatG`, `carbsG` values for that slot, and include `foodDescription` (a brief summary like "150g chicken + 200g rice")
        - If logging today's actual intake: call `log_meal_event` with status "eaten"
        - Always present the macro summary to the user before making any mutations

        **Distribution coaching (when meal macros are known):**
        - Check protein per meal: aim for ≥30g per meal for muscle protein synthesis
        - Flag front-loaded vs back-loaded patterns
        - If user's breakfast protein < 20g but dinner protein > 50g: suggest rebalancing
        - Protein target across meals: 3–4 doses of 30–40g, 3–5 hours apart

        **Predictive guidance:**
        - If you can see the current time and remaining meals, calculate if the user will hit their daily targets
        - Example: "You're at 95g protein, dinner provides 45g → you'll land at 140g vs 160g target. A 100g Greek yogurt at your snack would close the gap."

        **Silent attribution (default):**
        - When a user confirms eating a planned meal without changes, their macros are automatically attributed from the slot. You do NOT need to call `calculate_meal` for already-calculated slots.
        - Only call `calculate_meal` when something is new or different.

        **Tone:** Specific, mechanism-aware, optional. "Here's a pattern. Here are two options." Never "you should." Round all displayed values: protein/fat/carbs to nearest 5g, kcal to nearest 50.

        Current audited context snapshot:
        \(snapshot)
        """
    }
}
