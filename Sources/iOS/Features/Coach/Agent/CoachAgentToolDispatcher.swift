import Foundation

enum CoachToolDispatchError: Error, Equatable {
    case unknownTool(String)
    case invalidArgs(String)
    case missingContext(String)
    case mutationFailed(String)

    var message: String {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool '\(name)'"
        case .invalidArgs(let detail), .missingContext(let detail), .mutationFailed(let detail):
            return detail
        }
    }
}

@MainActor
struct CoachAgentToolDispatcher {
    let repository: ReadingRepository
    let macroPlanStore: MacroPlanStore
    let macroDeviationStore: MacroDeviationStore
    let macroUntrackedRangeStore: MacroUntrackedRangeStore
    let mealScheduleStore: MealScheduleStore
    let mealEventStore: MealEventStore
    let auditStore: CoachAgentAuditStore
    let mealCalculator: MealCalculator
    let scheduledNudgeStore: ScheduledNudgeStore?
    let activeCutProvider: () -> ActiveCut?
    let onMutation: (() -> Void)?
    let recordMemory: ((String) throws -> CoachAgentMemory)?
    let pinTodayNote: ((String) -> Void)?
    let nowProvider: () -> Date
    let calendar: Calendar

    init(
        repository: ReadingRepository,
        macroPlanStore: MacroPlanStore,
        macroDeviationStore: MacroDeviationStore,
        macroUntrackedRangeStore: MacroUntrackedRangeStore,
        mealScheduleStore: MealScheduleStore,
        mealEventStore: MealEventStore,
        auditStore: CoachAgentAuditStore,
        mealCalculator: MealCalculator,
        scheduledNudgeStore: ScheduledNudgeStore? = nil,
        activeCutProvider: @escaping () -> ActiveCut? = { ActiveCutStore.load() },
        onMutation: (() -> Void)? = nil,
        recordMemory: ((String) throws -> CoachAgentMemory)? = nil,
        pinTodayNote: ((String) -> Void)? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.macroPlanStore = macroPlanStore
        self.macroDeviationStore = macroDeviationStore
        self.macroUntrackedRangeStore = macroUntrackedRangeStore
        self.mealScheduleStore = mealScheduleStore
        self.mealEventStore = mealEventStore
        self.auditStore = auditStore
        self.mealCalculator = mealCalculator
        self.scheduledNudgeStore = scheduledNudgeStore
        self.activeCutProvider = activeCutProvider
        self.onMutation = onMutation
        self.recordMemory = recordMemory
        self.pinTodayNote = pinTodayNote
        self.nowProvider = nowProvider
        self.calendar = calendar
    }

    private static let decoder = JSONDecoder()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Match `CoachAgentSession.encoder`: emit ISO8601 with the user's
        // local timezone offset so day-keyed dates land on the same calendar
        // day the user sees in the app. UTC encoding shifts records back a
        // day for users east of UTC.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(CoachDateEncoding.iso8601Local.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func dispatch(
        name: String,
        argsJSON: Data,
        runID: UUID,
        providerCallID: String?,
        sequence: Int
    ) async throws -> Data {
        let requestedAt = nowProvider()
        guard let tool = CoachTool(rawValue: name) else {
            let error = CoachToolDispatchError.unknownTool(name)
            let errorData = encodeError(error.message)
            try await recordToolCall(
                runID: runID,
                providerCallID: providerCallID,
                sequence: sequence,
                toolName: name,
                status: .rejected,
                requestedAt: requestedAt,
                argumentsJSON: argsJSON,
                resultJSON: errorData,
                errorMessage: error.message
            )
            throw error
        }

        do {
            let result = try await execute(tool: tool, argsJSON: argsJSON, runID: runID)
            try await recordToolCall(
                runID: runID,
                providerCallID: providerCallID,
                sequence: sequence,
                toolName: name,
                status: .succeeded,
                requestedAt: requestedAt,
                argumentsJSON: argsJSON,
                resultJSON: result.data,
                errorMessage: nil,
                targetEntity: result.targetEntity,
                targetID: result.targetID,
                beforeJSON: result.beforeJSON,
                afterJSON: result.afterJSON
            )
            return result.data
        } catch let error as CoachToolDispatchError {
            let errorData = encodeError(error.message)
            try await recordToolCall(
                runID: runID,
                providerCallID: providerCallID,
                sequence: sequence,
                toolName: name,
                status: error.isRejected ? .rejected : .failed,
                requestedAt: requestedAt,
                argumentsJSON: argsJSON,
                resultJSON: errorData,
                errorMessage: error.message
            )
            throw error
        } catch {
            let message = error.localizedDescription
            let errorData = encodeError(message)
            try await recordToolCall(
                runID: runID,
                providerCallID: providerCallID,
                sequence: sequence,
                toolName: name,
                status: .failed,
                requestedAt: requestedAt,
                argumentsJSON: argsJSON,
                resultJSON: errorData,
                errorMessage: message
            )
            throw CoachToolDispatchError.mutationFailed(message)
        }
    }

    func makeSnapshot(historyDays requestedDays: Int? = nil) -> CoachSnapshotResult {
        let now = nowProvider()
        let historyDays = min(90, max(1, requestedDays ?? 21))
        let today = Reading.dayStart(of: now)
        let cutoff = calendar.date(byAdding: .day, value: -(historyDays - 1), to: today) ?? today

        let activeCut = activeCutProvider()
        let cutStart = activeCut.map { Reading.dayStart(of: $0.startDate) }
        let currentPlan = cutStart.flatMap { macroPlanStore.currentPeriod(forCutStartDate: $0) }
        let allReadings = repository.allReadings()
        let allSleep = repository.allSleepNights()
        let allActivity = repository.allDailyActivities()
        let allDeviations = cutStart.map { macroDeviationStore.deviations(forCutStartDate: $0) } ?? []
        let allRanges = cutStart.map { macroUntrackedRangeStore.ranges(forCutStartDate: $0) } ?? []

        let context = CutCoachContext(
            activeCut: activeCut,
            planPeriod: currentPlan.map(CutCoachMacroPlan.init),
            readings: allReadings.map(CutCoachReading.init),
            macroDeviations: allDeviations.map(CutCoachMacroDeviation.init),
            untrackedRanges: allRanges.map(CutCoachUntrackedRange.init),
            sleepNights: allSleep.map(CutCoachSleepNight.init),
            dailyActivities: allActivity.map(CutCoachDailyActivity.init),
            now: now,
            calendar: calendar
        )

        let recommendation = CutCoachEngine.evaluate(context: context)

        // Meal scheduling block: schedule + recent events + 14d stats
        let currentMealSchedule: CoachMealScheduleDTO? = {
            guard let cutStart, let period = mealScheduleStore.currentPeriod(forCutStartDate: cutStart) else {
                return nil
            }
            let slots = mealScheduleStore.slots(forScheduleId: period.id)
            return CoachMealScheduleDTO(period, slots: slots)
        }()
        let recentMealEvents = mealEventStore
            .eventsInLastDays(historyDays, now: now)
            .map(CoachMealEventDTO.init)
        let mealStats = computeMealStats(
            scheduleSlots: mealSlotsForActiveSchedule(cutStart: cutStart),
            now: now,
            windowDays: 14
        )

        return CoachSnapshotResult(
            activeCut: activeCut.map { CoachActiveCutDTO($0, now: now) },
            currentMacroPlan: currentPlan.map(CoachMacroPlanPeriodDTO.init),
            recentReadings: allReadings.filter { $0.date >= cutoff }.map(CoachReadingDTO.init),
            recentMacroDeviations: allDeviations.filter { $0.date >= cutoff }.map(CoachMacroDeviationDTO.init),
            recentUntrackedRanges: allRanges.filter { $0.endDate >= cutoff }.map(CoachUntrackedRangeDTO.init),
            recentSleep: allSleep.filter { $0.nightDate >= cutoff }.map(CoachSleepNightDTO.init),
            recentActivity: allActivity.filter { $0.day >= cutoff }.map(CoachDailyActivityDTO.init),
            recommendation: CoachRecommendationDTO(recommendation),
            currentMealSchedule: currentMealSchedule,
            recentMealEvents: recentMealEvents,
            mealStats: mealStats,
            generatedAt: now
        )
    }

    private func mealSlotsForActiveSchedule(cutStart: Date?) -> [MealSlot] {
        guard let cutStart, let period = mealScheduleStore.currentPeriod(forCutStartDate: cutStart) else {
            return []
        }
        return mealScheduleStore.slots(forScheduleId: period.id)
    }

    /// Compute timing pattern stats over a fixed `windowDays` window.
    /// Returns nil when there are fewer than 3 informative events.
    private func computeMealStats(scheduleSlots: [MealSlot], now: Date, windowDays: Int) -> CoachMealStatsDTO? {
        let events = mealEventStore.eventsInLastDays(windowDays, now: now)
        let total = events.count
        guard total >= 3 else { return nil }

        // Group events by `slotNameSnapshot` (case-insensitive). Events without a
        // snapshot fall back to "(unspecified)" so they still surface.
        var grouped: [String: [MealEvent]] = [:]
        for event in events {
            let key = (event.slotNameSnapshot ?? "(unspecified)").lowercased()
            grouped[key, default: []].append(event)
        }

        let slotByKey: [String: MealSlot] = Dictionary(
            uniqueKeysWithValues: scheduleSlots.map { ($0.name.lowercased(), $0) }
        )

        var perMeal: [CoachMealStatPerMealDTO] = []
        var skippedTotal = 0
        for (key, group) in grouped {
            let slot = slotByKey[key]
            let scheduledMinutes = slot?.minutesFromMidnight ?? 0
            let displayName = slot?.name ?? group.first?.slotNameSnapshot ?? key

            let logged = group.count
            let skipped = group.filter { $0.statusRaw == MealEventStatus.skipped.rawValue }.count
            skippedTotal += skipped
            let skipRate = logged == 0 ? 0 : Double(skipped) / Double(logged)

            // Delays only computed for eaten/partial events with a known scheduled time.
            let delays: [Int] = {
                guard let slot else { return [] }
                return group.compactMap { event -> Int? in
                    guard event.statusRaw != MealEventStatus.skipped.rawValue else { return nil }
                    return event.minutesFromMidnight - slot.minutesFromMidnight
                }
            }()
            let medianDelay: Int? = delays.isEmpty ? nil : median(delays)
            let lateCount = delays.filter { $0 > 60 }.count

            perMeal.append(CoachMealStatPerMealDTO(
                slotName: displayName,
                scheduledMinutes: scheduledMinutes,
                loggedCount: logged,
                skippedCount: skipped,
                skipRate: skipRate,
                medianDelayMinutes: medianDelay,
                lateCount: lateCount
            ))
        }

        return CoachMealStatsDTO(
            windowDays: windowDays,
            perMeal: perMeal.sorted(by: { $0.scheduledMinutes < $1.scheduledMinutes }),
            overallSkipRate: total == 0 ? 0 : Double(skippedTotal) / Double(total)
        )
    }

    private func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private func execute(tool: CoachTool, argsJSON: Data, runID: UUID) async throws -> DispatchExecutionResult {
        switch tool {
        case .getCoachSnapshot:
            let args = try decode(argsJSON, as: CoachSnapshotArgs.self)
            return .read(try encode(makeSnapshot(historyDays: args.historyDays)))
        case .listMacroPlanPeriods:
            let args = try decode(argsJSON, as: CoachCutScopedArgs.self)
            return .read(try encode(listMacroPlanPeriods(args)))
        case .listMacroDeviations:
            let args = try decode(argsJSON, as: ListMacroDeviationsArgs.self)
            return .read(try encode(listMacroDeviations(args)))
        case .listUntrackedRanges:
            let args = try decode(argsJSON, as: CoachCutScopedArgs.self)
            return .read(try encode(listUntrackedRanges(args)))
        case .appendCoachNote:
            let args = try decode(argsJSON, as: AppendCoachNoteArgs.self)
            return try await appendCoachNote(args, runID: runID)
        case .recordMemory:
            let args = try decode(argsJSON, as: RecordMemoryArgs.self)
            return try recordMemory(args)
        case .replaceCurrentMacroPlan:
            let args = try decode(argsJSON, as: ReplaceCurrentMacroPlanArgs.self)
            return try replaceCurrentMacroPlan(args)
        case .logMacroDeviation:
            let args = try decode(argsJSON, as: LogMacroDeviationArgs.self)
            return try logMacroDeviation(args)
        case .markUntrackedRange:
            let args = try decode(argsJSON, as: MarkUntrackedRangeArgs.self)
            return try markUntrackedRange(args)
        case .getMealSchedule:
            let args = try decode(argsJSON, as: GetMealScheduleArgs.self)
            return .read(try encode(getMealSchedule(args)))
        case .replaceCurrentMealSchedule:
            let args = try decode(argsJSON, as: ReplaceCurrentMealScheduleArgs.self)
            return try replaceCurrentMealSchedule(args)
        case .logMealEvent:
            let args = try decode(argsJSON, as: LogMealEventArgs.self)
            return try logMealEvent(args)
        case .calculateMeal:
            let args = try decode(argsJSON, as: CalculateMealArgs.self)
            return try await calculateMeal(args)
        case .scheduleNudge:
            let args = try decode(argsJSON, as: ScheduleNudgeArgs.self)
            return try scheduleNudge(args)
        case .cancelNudge:
            let args = try decode(argsJSON, as: CancelNudgeArgs.self)
            return try cancelNudge(args)
        case .setStepTarget:
            let args = try decode(argsJSON, as: SetStepTargetArgs.self)
            return try setStepTarget(args)
        case .scheduleDietBreak:
            let args = try decode(argsJSON, as: ScheduleDietBreakArgs.self)
            return try scheduleDietBreak(args)
        case .scheduleRefeed:
            let args = try decode(argsJSON, as: ScheduleRefeedArgs.self)
            return try scheduleRefeed(args)
        case .proposeMealPlan:
            let args = try decode(argsJSON, as: ProposeMealPlanArgs.self)
            return try await proposeMealPlan(args)
        case .pinTodayNote:
            let args = try decode(argsJSON, as: PinTodayNoteArgs.self)
            return try executePinTodayNote(args)
        }
    }

    private func listMacroPlanPeriods(_ args: CoachCutScopedArgs) throws -> CoachPlanPeriodsResult {
        let cutStart = try resolveActiveCutStart(args.cutStartDate)
        let periods = limited(macroPlanStore.periods(forCutStartDate: cutStart), limit: args.limit)
        return CoachPlanPeriodsResult(cutStartDate: cutStart, periods: periods.map(CoachMacroPlanPeriodDTO.init))
    }

    private func listMacroDeviations(_ args: ListMacroDeviationsArgs) throws -> CoachMacroDeviationsResult {
        let cutStart = try resolveActiveCutStart(args.cutStartDate)
        let fromDate = try args.fromDate.map(parseDay)
        let toDate = try args.toDate.map(parseDay)
        if let fromDate, let toDate, fromDate > toDate {
            throw CoachToolDispatchError.invalidArgs("fromDate must be on or before toDate")
        }

        let filtered = macroDeviationStore.deviations(forCutStartDate: cutStart).filter { deviation in
            if let fromDate, deviation.date < fromDate { return false }
            if let toDate, deviation.date > toDate { return false }
            return true
        }
        return CoachMacroDeviationsResult(
            cutStartDate: cutStart,
            deviations: limited(filtered, limit: args.limit).map(CoachMacroDeviationDTO.init)
        )
    }

    private func listUntrackedRanges(_ args: CoachCutScopedArgs) throws -> CoachUntrackedRangesResult {
        let cutStart = try resolveActiveCutStart(args.cutStartDate)
        let ranges = limited(macroUntrackedRangeStore.ranges(forCutStartDate: cutStart), limit: args.limit)
        return CoachUntrackedRangesResult(cutStartDate: cutStart, ranges: ranges.map(CoachUntrackedRangeDTO.init))
    }

    private func appendCoachNote(_ args: AppendCoachNoteArgs, runID: UUID) async throws -> DispatchExecutionResult {
        let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CoachToolDispatchError.invalidArgs("append_coach_note.text cannot be empty")
        }
        guard text.count <= 1_200 else {
            throw CoachToolDispatchError.invalidArgs("append_coach_note.text must be 1200 characters or fewer")
        }

        let cutStart = try args.cutStartDate.map(resolveActiveCutStart)
            ?? activeCutProvider().map { Reading.dayStart(of: $0.startDate) }
        let day = try args.day.map(parseDay)
        let kind = args.kind ?? "observation"
        let visibility = args.visibility ?? "userVisible"
        try validateNoteKind(kind)
        try validateNoteVisibility(visibility)

        let noteID = try await auditStore.appendCoachNote(CoachAgentNoteAuditRecord(
            runID: runID,
            source: "agent",
            kind: kind,
            visibility: visibility,
            cutStartDate: cutStart,
            day: day,
            text: text,
            payloadJSON: nil,
            audioDraftID: nil,
            createdAt: nowProvider()
        ))

        let result = CoachNoteMutationResult(
            id: noteID,
            runID: runID,
            text: text,
            kind: kind,
            visibility: visibility,
            cutStartDate: cutStart,
            day: day
        )
        let resultData = try encode(result)
        return DispatchExecutionResult(
            data: resultData,
            targetEntity: "coach_note",
            targetID: noteID,
            beforeJSON: nil,
            afterJSON: resultData
        )
    }

    private func recordMemory(_ args: RecordMemoryArgs) throws -> DispatchExecutionResult {
        guard let recordMemory else {
            throw CoachToolDispatchError.missingContext("Agent memory storage is unavailable")
        }
        let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CoachToolDispatchError.invalidArgs("record_memory.text cannot be empty")
        }
        guard text.count <= 1_000 else {
            throw CoachToolDispatchError.invalidArgs("record_memory.text must be 1000 characters or fewer")
        }
        let memory = try recordMemory(text)
        let resultData = try encode(CoachMemoryMutationResult(memory: memory))
        return DispatchExecutionResult(
            data: resultData,
            targetEntity: "agent_memory",
            targetID: memory.id,
            beforeJSON: nil,
            afterJSON: resultData
        )
    }

    private func executePinTodayNote(_ args: PinTodayNoteArgs) throws -> DispatchExecutionResult {
        let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CoachToolDispatchError.invalidArgs("pin_today_note.text cannot be empty")
        }
        guard text.count <= 200 else {
            throw CoachToolDispatchError.invalidArgs("pin_today_note.text must be 200 characters or fewer")
        }
        pinTodayNote?(text)
        let result = try encode(["status": "pinned", "text": text])
        return DispatchExecutionResult(data: result, targetEntity: "today_pinned_note", targetID: nil, beforeJSON: nil, afterJSON: result)
    }

    private func replaceCurrentMacroPlan(_ args: ReplaceCurrentMacroPlanArgs) throws -> DispatchExecutionResult {
        let cutStart = try resolveActiveCutStart(args.cutStartDate)
        guard (800...6_000).contains(args.kcal) else {
            throw CoachToolDispatchError.invalidArgs("kcal must be between 800 and 6000")
        }
        try validateGrams(args.proteinG, name: "proteinG", max: 500)
        try validateGrams(args.fatG, name: "fatG", max: 500)
        try validateGrams(args.carbsG, name: "carbsG", max: 1_000)

        let tag = try parseMacroPlanTag(args.tag)
        let customLabel = trimmedOptional(args.customTagLabel)
        if tag == .custom && customLabel == nil {
            throw CoachToolDispatchError.invalidArgs("customTagLabel is required when tag is custom")
        }

        let before = macroPlanStore.currentPeriod(forCutStartDate: cutStart).map(CoachMacroPlanPeriodDTO.init)
        let period = macroPlanStore.replaceCurrentPeriod(
            cutStartDate: cutStart,
            kcal: args.kcal,
            proteinG: args.proteinG,
            fatG: args.fatG,
            carbsG: args.carbsG,
            tag: tag,
            customTagLabel: customLabel,
            note: trimmedOptional(args.note),
            now: nowProvider()
        )
        onMutation?()

        let after = CoachMacroPlanPeriodDTO(period)
        let result = CoachMacroPlanMutationResult(period: after)
        return try DispatchExecutionResult(
            data: encode(result),
            targetEntity: "macro_plan_period",
            targetID: period.id,
            beforeJSON: encodeOptional(before),
            afterJSON: encodeOptional(after)
        )
    }

    private func logMacroDeviation(_ args: LogMacroDeviationArgs) throws -> DispatchExecutionResult {
        let cutStart = try resolveActiveCutStart(args.cutStartDate)
        let day = try parseDay(args.date)
        guard let direction = MacroDirection(rawValue: args.direction) else {
            throw CoachToolDispatchError.invalidArgs("direction must be one of: over, under, unknown")
        }
        guard let magnitude = MacroMagnitude(rawValue: args.magnitude) else {
            throw CoachToolDispatchError.invalidArgs("magnitude must be one of: slight, moderate, large, wayOff")
        }

        let before = macroDeviationStore.deviation(on: day, cutStartDate: cutStart).map(CoachMacroDeviationDTO.init)
        let deviation: MacroDeviation
        do {
            deviation = try macroDeviationStore.upsert(
                date: day,
                cutStartDate: cutStart,
                direction: direction,
                magnitude: magnitude,
                note: trimmedOptional(args.note),
                now: nowProvider()
            )
        } catch let error as MacroDeviationError {
            throw CoachToolDispatchError.invalidArgs(message(for: error))
        } catch {
            throw CoachToolDispatchError.mutationFailed("Could not log macro deviation: \(error.localizedDescription)")
        }
        onMutation?()

        let after = CoachMacroDeviationDTO(deviation)
        let result = CoachMacroDeviationMutationResult(deviation: after)
        return try DispatchExecutionResult(
            data: encode(result),
            targetEntity: "macro_deviation",
            targetID: deviation.id,
            beforeJSON: encodeOptional(before),
            afterJSON: encodeOptional(after)
        )
    }

    private func markUntrackedRange(_ args: MarkUntrackedRangeArgs) throws -> DispatchExecutionResult {
        let cutStart = try resolveActiveCutStart(args.cutStartDate)
        let start = try parseDay(args.startDate)
        let end = try parseDay(args.endDate)
        guard let reason = UntrackedReason(rawValue: args.reason) else {
            throw CoachToolDispatchError.invalidArgs("reason must be one of: travel, illness, life, custom")
        }
        let customLabel = trimmedOptional(args.customReasonLabel)
        if reason == .custom && customLabel == nil {
            throw CoachToolDispatchError.invalidArgs("customReasonLabel is required when reason is custom")
        }

        let range: MacroUntrackedRange
        do {
            range = try macroUntrackedRangeStore.insert(
                cutStartDate: cutStart,
                startDate: start,
                endDate: end,
                reason: reason,
                customReasonLabel: customLabel,
                now: nowProvider()
            )
        } catch let error as MacroUntrackedRangeError {
            throw CoachToolDispatchError.invalidArgs(message(for: error))
        } catch {
            throw CoachToolDispatchError.mutationFailed("Could not mark untracked range: \(error.localizedDescription)")
        }
        onMutation?()

        let after = CoachUntrackedRangeDTO(range)
        let result = CoachUntrackedRangeMutationResult(range: after)
        return try DispatchExecutionResult(
            data: encode(result),
            targetEntity: "macro_untracked_range",
            targetID: range.id,
            beforeJSON: nil,
            afterJSON: encodeOptional(after)
        )
    }

    // MARK: - Meal scheduling tools

    private func getMealSchedule(_ args: GetMealScheduleArgs) throws -> CoachMealScheduleResult {
        let cutStart = try resolveActiveCutStart(args.cutStartDate)
        let now = nowProvider()
        let historyDays = min(90, max(1, args.historyDays ?? 14))

        let scheduleDTO: CoachMealScheduleDTO? = {
            guard let period = mealScheduleStore.currentPeriod(forCutStartDate: cutStart) else { return nil }
            let slots = mealScheduleStore.slots(forScheduleId: period.id)
            return CoachMealScheduleDTO(period, slots: slots)
        }()

        let events = mealEventStore.eventsInLastDays(historyDays, now: now)
        let stats = computeMealStats(
            scheduleSlots: mealSlotsForActiveSchedule(cutStart: cutStart),
            now: now,
            windowDays: 14
        )

        return CoachMealScheduleResult(
            schedule: scheduleDTO,
            recentEvents: events.map(CoachMealEventDTO.init),
            stats: stats,
            generatedAt: now
        )
    }

    private func replaceCurrentMealSchedule(_ args: ReplaceCurrentMealScheduleArgs) throws -> DispatchExecutionResult {
        let cutStart = try resolveActiveCutStart(args.cutStartDate)

        guard !args.slots.isEmpty else {
            throw CoachToolDispatchError.invalidArgs("slots must contain at least one entry")
        }
        guard args.slots.count <= 12 else {
            throw CoachToolDispatchError.invalidArgs("slots must contain at most 12 entries")
        }

        var seenNames = Set<String>()
        var lastMinutes = -1
        var inputs: [MealSlotInput] = []
        for (idx, slot) in args.slots.enumerated() {
            let trimmedName = slot.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw CoachToolDispatchError.invalidArgs("slot[\(idx)].name cannot be empty")
            }
            let lowered = trimmedName.lowercased()
            guard seenNames.insert(lowered).inserted else {
                throw CoachToolDispatchError.invalidArgs("duplicate meal name '\(trimmedName)'")
            }

            let parsed = try parseTimeOfDay(slot.time)
            guard parsed.minutesFromMidnight > lastMinutes else {
                throw CoachToolDispatchError.invalidArgs("slot times must be strictly increasing; '\(slot.time)' is out of order")
            }
            lastMinutes = parsed.minutesFromMidnight

            let kind: MealKind
            if let raw = slot.kind?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                guard let parsedKind = MealKind(rawValue: raw) else {
                    throw CoachToolDispatchError.invalidArgs("kind must be one of: breakfast, lunch, dinner, snack, preWorkout, postWorkout, custom")
                }
                kind = parsedKind
            } else {
                kind = .custom
            }

            try validatePercent(slot.kcalPercent, name: "kcalPercent")
            try validatePercent(slot.proteinPercent, name: "proteinPercent")
            try validatePercent(slot.fatPercent, name: "fatPercent")
            try validatePercent(slot.carbsPercent, name: "carbsPercent")

            try validateAbsoluteMacro(slot.kcal, name: "kcal", max: 6_000)
            try validateAbsoluteMacro(slot.proteinG, name: "proteinG", max: 500)
            try validateAbsoluteMacro(slot.fatG, name: "fatG", max: 500)
            try validateAbsoluteMacro(slot.carbsG, name: "carbsG", max: 1_000)

            // Stamp `calculatedAt` whenever the coach passed at least one
            // absolute macro for this slot so the UI can show "calculated 2h
            // ago" badges and the cache knows when to expire.
            let hasCalculated = slot.kcal != nil
                || slot.proteinG != nil
                || slot.fatG != nil
                || slot.carbsG != nil
            let foodDescription = trimmedOptional(slot.foodDescription)

            inputs.append(MealSlotInput(
                name: trimmedName,
                minutesFromMidnight: parsed.minutesFromMidnight,
                kind: kind,
                sortOrder: idx,
                kcalPercent: slot.kcalPercent,
                proteinPercent: slot.proteinPercent,
                fatPercent: slot.fatPercent,
                carbsPercent: slot.carbsPercent,
                calculatedKcal: slot.kcal,
                calculatedProteinG: slot.proteinG,
                calculatedFatG: slot.fatG,
                calculatedCarbsG: slot.carbsG,
                calculatedAt: hasCalculated ? nowProvider() : nil,
                foodDescription: foodDescription
            ))
        }

        let beforeDTO: CoachMealScheduleDTO? = {
            guard let p = mealScheduleStore.currentPeriod(forCutStartDate: cutStart) else { return nil }
            let slots = mealScheduleStore.slots(forScheduleId: p.id)
            return CoachMealScheduleDTO(p, slots: slots)
        }()

        let period: MealSchedulePeriod
        do {
            period = try mealScheduleStore.replaceCurrentPeriod(
                cutStartDate: cutStart,
                slotInputs: inputs,
                note: trimmedOptional(args.note),
                now: nowProvider()
            )
        } catch {
            throw CoachToolDispatchError.mutationFailed("Could not replace meal schedule: \(error.localizedDescription)")
        }
        onMutation?()

        let afterSlots = mealScheduleStore.slots(forScheduleId: period.id)
        let afterDTO = CoachMealScheduleDTO(period, slots: afterSlots)
        let result = CoachMealScheduleMutationResult(schedule: afterDTO)
        return try DispatchExecutionResult(
            data: encode(result),
            targetEntity: "meal_schedule_period",
            targetID: period.id,
            beforeJSON: encodeOptional(beforeDTO),
            afterJSON: encodeOptional(afterDTO)
        )
    }

    private func logMealEvent(_ args: LogMealEventArgs) throws -> DispatchExecutionResult {
        guard let status = MealEventStatus(rawValue: args.status) else {
            throw CoachToolDispatchError.invalidArgs("status must be one of: eaten, skipped, partial")
        }
        let allowedCaptured: Set<String> = ["tap", "voice", "agent"]
        guard allowedCaptured.contains(args.capturedFrom) else {
            throw CoachToolDispatchError.invalidArgs("capturedFrom must be one of: tap, voice, agent")
        }
        let allowedQuality: Set<String> = ["exact", "approximate", "unknown"]
        guard allowedQuality.contains(args.timeQuality) else {
            throw CoachToolDispatchError.invalidArgs("timeQuality must be one of: exact, approximate, unknown")
        }

        let day = try parseDay(args.date)
        let now = nowProvider()
        let today = Reading.dayStart(of: now)
        guard day <= today else {
            throw CoachToolDispatchError.invalidArgs("date cannot be in the future")
        }
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        guard daysAgo <= 7 else {
            throw CoachToolDispatchError.invalidArgs("date is more than 7 days in the past")
        }

        let trimmedName = args.mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CoachToolDispatchError.invalidArgs("mealName cannot be empty")
        }

        if status == .skipped, let raw = args.ateAt, !raw.isEmpty {
            throw CoachToolDispatchError.invalidArgs("ateAt must be omitted when status is skipped")
        }
        if (status == .eaten || status == .partial) && args.timeQuality != "unknown" {
            guard let raw = args.ateAt, !raw.isEmpty else {
                throw CoachToolDispatchError.invalidArgs("ateAt is required for status \(status.rawValue) unless timeQuality is unknown")
            }
            _ = try parseTimeOfDay(raw)
        }

        // Resolve slot from active schedule by case-insensitive name when possible.
        let cutStart = activeCutProvider().map { Reading.dayStart(of: $0.startDate) }
        let activePeriod = cutStart.flatMap { mealScheduleStore.currentPeriod(forCutStartDate: $0) }
        let activeSlots = activePeriod.map { mealScheduleStore.slots(forScheduleId: $0.id) } ?? []
        let matchedSlot = activeSlots.first { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }

        // Compose `ateAt` Date for the event.
        let ateAt: Date
        if let raw = args.ateAt, !raw.isEmpty {
            ateAt = try ateAtDate(timeStr: raw, day: day)
        } else if let matchedSlot {
            // Fall back to slot's scheduled time when ateAt was omitted.
            let h = matchedSlot.minutesFromMidnight / 60
            let m = matchedSlot.minutesFromMidnight % 60
            ateAt = calendar.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
        } else {
            // No slot, no ateAt: stamp at the day boundary so we still record something.
            ateAt = day
        }

        let hungerBefore = try args.hungerBefore.map(parseHunger)
        let hungerAfter = try args.hungerAfter.map(parseHunger)

        let beforeDTO = matchedSlot
            .flatMap { mealEventStore.event(on: day, slotId: $0.id) }
            .map(CoachMealEventDTO.init)

        let event = mealEventStore.upsert(
            slotId: matchedSlot?.id,
            slotNameSnapshot: matchedSlot?.name ?? trimmedName,
            scheduleId: activePeriod?.id,
            ateAt: ateAt,
            status: status,
            hungerBefore: hungerBefore,
            hungerAfter: hungerAfter,
            note: trimmedOptional(args.note),
            now: now
        )
        onMutation?()

        let after = CoachMealEventDTO(event)
        let result = CoachMealEventMutationResult(event: after)
        return try DispatchExecutionResult(
            data: encode(result),
            targetEntity: "meal_event",
            targetID: event.id,
            beforeJSON: encodeOptional(beforeDTO),
            afterJSON: encodeOptional(after)
        )
    }

    // MARK: - calculate_meal

    /// Pure-compute tool: parse food → look up nutrition → return per-item and
    /// total macros. Performs no audit-relevant mutations; the coach is
    /// expected to follow up with `replace_current_meal_schedule` or
    /// `log_meal_event` if the result should be persisted.
    private func calculateMeal(_ args: CalculateMealArgs) async throws -> DispatchExecutionResult {
        let trimmedItems = args.items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedItems.isEmpty else {
            throw CoachToolDispatchError.invalidArgs("calculate_meal.items must contain at least one entry")
        }
        guard trimmedItems.count <= MealCalculator.maxItems else {
            throw CoachToolDispatchError.invalidArgs(
                "calculate_meal.items must contain at most \(MealCalculator.maxItems) entries"
            )
        }

        let mealName = trimmedOptional(args.mealName)
        let assumeRaw = args.assumeRawWhenAmbiguous ?? true

        let computed: CalculateMealResult
        do {
            computed = try await mealCalculator.calculate(
                items: trimmedItems,
                assumeRawWhenAmbiguous: assumeRaw
            )
        } catch let error as MealCalculatorError {
            throw CoachToolDispatchError.mutationFailed(error.localizedDescription)
        } catch {
            throw CoachToolDispatchError.mutationFailed(
                "Could not calculate meal: \(error.localizedDescription)"
            )
        }

        let dto = CoachCalculateMealResult(from: computed, mealName: mealName)
        return .read(try encode(dto))
    }

    // MARK: - Nudge tools

    private func scheduleNudge(_ args: ScheduleNudgeArgs) throws -> DispatchExecutionResult {
        let trimmedMessage = args.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw CoachToolDispatchError.invalidArgs("schedule_nudge.message cannot be empty")
        }

        let isoFormatter = ISO8601DateFormatter()
        let isoFormatterWithFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        guard let scheduledAt = isoFormatter.date(from: args.scheduledAt)
            ?? isoFormatterWithFractional.date(from: args.scheduledAt)
        else {
            throw CoachToolDispatchError.invalidArgs("scheduledAt must be ISO-8601, got '\(args.scheduledAt)'")
        }

        let expiresAt: Date?
        if let raw = args.expiresAt, !raw.isEmpty {
            guard let parsed = isoFormatter.date(from: raw) ?? isoFormatterWithFractional.date(from: raw) else {
                throw CoachToolDispatchError.invalidArgs("expiresAt must be ISO-8601, got '\(raw)'")
            }
            expiresAt = parsed
        } else {
            expiresAt = nil
        }

        guard let store = scheduledNudgeStore else {
            return .read(try encode(["status": "nudge_scheduling_unavailable"]))
        }

        let triggerParams = "{\"fireAt\":\"\(isoFormatter.string(from: scheduledAt))\"}"
        let nudge = store.schedule(
            message: trimmedMessage,
            triggerType: .timeOfDay,
            triggerParams: triggerParams,
            expiresAt: expiresAt
        )
        onMutation?()

        let payload: [String: String] = [
            "nudgeId": nudge.id.uuidString,
            "scheduledAt": isoFormatter.string(from: scheduledAt)
        ]
        let resultData = try encode(payload)
        return DispatchExecutionResult(
            data: resultData,
            targetEntity: "scheduled_nudge",
            targetID: nudge.id,
            beforeJSON: nil,
            afterJSON: resultData
        )
    }

    private func cancelNudge(_ args: CancelNudgeArgs) throws -> DispatchExecutionResult {
        let trimmed = args.nudgeId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed) else {
            throw CoachToolDispatchError.invalidArgs("nudgeId must be a UUID, got '\(args.nudgeId)'")
        }
        guard let store = scheduledNudgeStore else {
            return .read(try encode(["status": "nudge_scheduling_unavailable"]))
        }
        store.cancel(id: uuid)
        onMutation?()
        let payload: [String: String] = ["status": "cancelled", "nudgeId": uuid.uuidString]
        let resultData = try encode(payload)
        return DispatchExecutionResult(
            data: resultData,
            targetEntity: "scheduled_nudge",
            targetID: uuid,
            beforeJSON: nil,
            afterJSON: resultData
        )
    }

    private func setStepTarget(_ args: SetStepTargetArgs) throws -> DispatchExecutionResult {
        guard (2_000...20_000).contains(args.dailySteps) else {
            throw CoachToolDispatchError.invalidArgs("dailySteps must be between 2000 and 20000")
        }
        UserDefaults.standard.set(args.dailySteps, forKey: "coach.dailyStepTarget")
        NotificationCenter.default.post(name: .activityTargetDidChange, object: nil)
        onMutation?()

        var payload: [String: String] = ["dailySteps": String(args.dailySteps)]
        if let rationale = trimmedOptional(args.rationale) {
            payload["rationale"] = rationale
        }
        let resultData = try encode(payload)
        return DispatchExecutionResult(
            data: resultData,
            targetEntity: "step_target",
            targetID: nil,
            beforeJSON: nil,
            afterJSON: resultData
        )
    }

    private func scheduleDietBreak(_ args: ScheduleDietBreakArgs) throws -> DispatchExecutionResult {
        guard (7...21).contains(args.durationDays) else {
            throw CoachToolDispatchError.invalidArgs("durationDays must be between 7 and 21")
        }
        guard (800...6_000).contains(args.kcal) else {
            throw CoachToolDispatchError.invalidArgs("kcal must be between 800 and 6000")
        }
        try validateGrams(args.proteinG, name: "proteinG", max: 500)

        let cutStart = try resolveActiveCutStart(nil)
        if let raw = args.startDate {
            _ = try parseDay(raw) // validate format only
        }

        let currentPeriod = macroPlanStore.currentPeriod(forCutStartDate: cutStart)
        let resolvedProtein = args.proteinG ?? currentPeriod?.proteinG
        let resolvedFat = currentPeriod?.fatG

        let before = currentPeriod.map(CoachMacroPlanPeriodDTO.init)
        let period = macroPlanStore.replaceCurrentPeriod(
            cutStartDate: cutStart,
            kcal: args.kcal,
            proteinG: resolvedProtein,
            fatG: resolvedFat,
            carbsG: nil,
            tag: .dietBreak,
            customTagLabel: nil,
            note: trimmedOptional(args.note),
            now: nowProvider()
        )
        onMutation?()

        let after = CoachMacroPlanPeriodDTO(period)
        let result = CoachMacroPlanMutationResult(period: after)
        return try DispatchExecutionResult(
            data: encode(result),
            targetEntity: "macro_plan_period",
            targetID: period.id,
            beforeJSON: encodeOptional(before),
            afterJSON: encodeOptional(after)
        )
    }

    private func scheduleRefeed(_ args: ScheduleRefeedArgs) throws -> DispatchExecutionResult {
        guard (800...6_000).contains(args.kcal) else {
            throw CoachToolDispatchError.invalidArgs("kcal must be between 800 and 6000")
        }
        try validateGrams(args.carbsG, name: "carbsG", max: 1_000)
        try validateGrams(args.proteinG, name: "proteinG", max: 500)
        try validateGrams(args.fatG, name: "fatG", max: 500)

        let cutStart = try resolveActiveCutStart(nil)
        let currentPeriod = macroPlanStore.currentPeriod(forCutStartDate: cutStart)
        let resolvedProtein = args.proteinG ?? currentPeriod?.proteinG
        let resolvedFat = args.fatG ?? currentPeriod?.fatG

        let before = currentPeriod.map(CoachMacroPlanPeriodDTO.init)
        let period = macroPlanStore.replaceCurrentPeriod(
            cutStartDate: cutStart,
            kcal: args.kcal,
            proteinG: resolvedProtein,
            fatG: resolvedFat,
            carbsG: args.carbsG,
            tag: .refeed,
            customTagLabel: nil,
            note: trimmedOptional(args.note),
            now: nowProvider()
        )
        onMutation?()

        let after = CoachMacroPlanPeriodDTO(period)
        let result = CoachMacroPlanMutationResult(period: after)
        return try DispatchExecutionResult(
            data: encode(result),
            targetEntity: "macro_plan_period",
            targetID: period.id,
            beforeJSON: encodeOptional(before),
            afterJSON: encodeOptional(after)
        )
    }

    private func proposeMealPlan(_ args: ProposeMealPlanArgs) async throws -> DispatchExecutionResult {
        let mealName = args.mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mealName.isEmpty else {
            throw CoachToolDispatchError.invalidArgs("mealName cannot be empty")
        }
        guard args.targetKcal > 0 else {
            throw CoachToolDispatchError.invalidArgs("targetKcal must be greater than 0")
        }
        guard args.targetProteinG > 0 else {
            throw CoachToolDispatchError.invalidArgs("targetProteinG must be greater than 0")
        }

        // Build a natural-language description that the calculator's LLM can
        // translate into a concrete food list. The macro and preference
        // constraints become the brief; the calculator returns one combination
        // with per-item grams and computed macros.
        var promptParts: [String] = []
        promptParts.append("Suggest a single \(mealName) hitting approximately \(args.targetKcal) kcal and \(args.targetProteinG)g protein")
        if let fat = args.targetFatG { promptParts.append("with about \(fat)g fat") }
        if let carbs = args.targetCarbsG { promptParts.append("with about \(carbs)g carbs") }
        if let prefs = args.preferences, !prefs.isEmpty {
            promptParts.append("Prefer: \(prefs.joined(separator: ", "))")
        }
        if let excludes = args.excludes, !excludes.isEmpty {
            promptParts.append("Exclude: \(excludes.joined(separator: ", "))")
        }
        let prompt = promptParts.joined(separator: ". ")

        let computed: CalculateMealResult
        do {
            computed = try await mealCalculator.calculate(
                items: [prompt],
                assumeRawWhenAmbiguous: true
            )
        } catch let error as MealCalculatorError {
            throw CoachToolDispatchError.mutationFailed(error.localizedDescription)
        } catch {
            throw CoachToolDispatchError.mutationFailed("Could not propose meal plan: \(error.localizedDescription)")
        }

        let dto = CoachCalculateMealResult(from: computed, mealName: mealName)
        return .read(try encode(dto))
    }

    private func validateAbsoluteMacro(_ value: Int?, name: String, max: Int) throws {
        guard let value else { return }
        guard (0...max).contains(value) else {
            throw CoachToolDispatchError.invalidArgs("\(name) must be between 0 and \(max)")
        }
    }

    private func parseTimeOfDay(_ raw: String) throws -> (hour: Int, minute: Int, minutesFromMidnight: Int) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute)
        else {
            throw CoachToolDispatchError.invalidArgs("time must be HH:mm 24-hour, got '\(raw)'")
        }
        return (hour, minute, hour * 60 + minute)
    }

    private func ateAtDate(timeStr: String, day: Date) throws -> Date {
        let parsed = try parseTimeOfDay(timeStr)
        guard let date = calendar.date(bySettingHour: parsed.hour, minute: parsed.minute, second: 0, of: day) else {
            throw CoachToolDispatchError.invalidArgs("Could not combine date and time '\(timeStr)'")
        }
        return date
    }

    private func parseHunger(_ raw: String) throws -> HungerLevel {
        guard let level = HungerLevel(rawValue: raw) else {
            throw CoachToolDispatchError.invalidArgs("hunger level must be one of: low, moderate, high")
        }
        return level
    }

    private func validatePercent(_ value: Double?, name: String) throws {
        guard let value else { return }
        guard value >= 0, value <= 1 else {
            throw CoachToolDispatchError.invalidArgs("\(name) must be between 0 and 1")
        }
    }

    private func recordToolCall(
        runID: UUID,
        providerCallID: String?,
        sequence: Int,
        toolName: String,
        status: CoachAgentToolAuditStatus,
        requestedAt: Date,
        argumentsJSON: Data,
        resultJSON: Data?,
        errorMessage: String?,
        targetEntity: String? = nil,
        targetID: UUID? = nil,
        beforeJSON: Data? = nil,
        afterJSON: Data? = nil
    ) async throws {
        let key = [runID.uuidString, String(sequence), providerCallID ?? "local", toolName].joined(separator: ":")
        try await auditStore.recordToolCall(CoachAgentToolCallAuditRecord(
            runID: runID,
            providerCallID: providerCallID,
            sequence: sequence,
            toolName: toolName,
            status: status,
            requestedAt: requestedAt,
            completedAt: nowProvider(),
            argumentsJSON: argumentsJSON,
            resultJSON: resultJSON,
            errorMessage: errorMessage,
            targetEntity: targetEntity,
            targetID: targetID,
            beforeJSON: beforeJSON,
            afterJSON: afterJSON,
            idempotencyKey: key
        ))
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw CoachToolDispatchError.invalidArgs("Failed to decode \(T.self): \(error.localizedDescription)")
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try Self.encoder.encode(value)
        } catch {
            throw CoachToolDispatchError.mutationFailed("Failed to encode result: \(error.localizedDescription)")
        }
    }

    private func encodeOptional<T: Encodable>(_ value: T?) throws -> Data? {
        guard let value else { return nil }
        return try encode(value)
    }

    private func encodeError(_ message: String) -> Data {
        let payload = ["error": message]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            ?? Data("{\"error\":\"unknown\"}".utf8)
    }

    private func resolveActiveCutStart(_ raw: String?) throws -> Date {
        let activeStart = activeCutProvider().map { Reading.dayStart(of: $0.startDate) }
        guard let raw else {
            guard let activeStart else {
                throw CoachToolDispatchError.missingContext("No active cut is available")
            }
            return activeStart
        }

        let parsed = try parseDay(raw)
        if let activeStart, parsed != activeStart {
            throw CoachToolDispatchError.invalidArgs("cutStartDate must match the active cut")
        }
        return parsed
    }

    private func parseDay(_ raw: String) throws -> Date {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let day = Self.dayFormatter.date(from: trimmed) {
            return Reading.dayStart(of: day)
        }
        if let date = Self.isoFormatter.date(from: trimmed) {
            return Reading.dayStart(of: date)
        }
        throw CoachToolDispatchError.invalidArgs("Expected yyyy-MM-dd date, got '\(raw)'")
    }

    private func parseMacroPlanTag(_ raw: String?) throws -> MacroPlanTag {
        guard let raw, !raw.isEmpty else { return .standard }
        guard let tag = MacroPlanTag(rawValue: raw) else {
            throw CoachToolDispatchError.invalidArgs("tag must be one of: standard, refeed, dietBreak, custom")
        }
        return tag
    }

    private func validateGrams(_ value: Int?, name: String, max: Int) throws {
        guard let value else { return }
        guard (0...max).contains(value) else {
            throw CoachToolDispatchError.invalidArgs("\(name) must be between 0 and \(max)")
        }
    }

    private func validateNoteKind(_ kind: String) throws {
        let allowed = ["checkIn", "observation", "planReason", "foodContext", "trainingContext", "sleepContext", "moodContext", "digestionContext", "internalAudit"]
        guard allowed.contains(kind) else {
            throw CoachToolDispatchError.invalidArgs("kind must be one of: \(allowed.joined(separator: ", "))")
        }
    }

    private func validateNoteVisibility(_ visibility: String) throws {
        let allowed = ["userVisible", "auditOnly"]
        guard allowed.contains(visibility) else {
            throw CoachToolDispatchError.invalidArgs("visibility must be userVisible or auditOnly")
        }
    }

    private func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func limited<T>(_ values: [T], limit: Int?) -> [T] {
        guard let limit, limit > 0 else { return values }
        return Array(values.prefix(limit))
    }

    private func message(for error: MacroDeviationError) -> String {
        switch error {
        case .futureDate:
            return "Cannot log a macro deviation in the future"
        case .beyondBackfillWindow:
            return "Macro deviation is outside the 30 day backfill window"
        case .insideUntrackedRange:
            return "That day is inside an untracked range"
        case .frozenOutsideEditWindow:
            return "Existing macro deviation is outside the 7 day edit window"
        case .noActivePlan:
            return "No macro plan covers that day"
        }
    }

    private func message(for error: MacroUntrackedRangeError) -> String {
        switch error {
        case .invalidRange:
            return "startDate must be on or before endDate"
        case .futureEnd:
            return "endDate cannot be in the future"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()
}

private extension CoachToolDispatchError {
    var isRejected: Bool {
        switch self {
        case .unknownTool, .invalidArgs, .missingContext:
            return true
        case .mutationFailed:
            return false
        }
    }
}

private struct DispatchExecutionResult {
    var data: Data
    var targetEntity: String?
    var targetID: UUID?
    var beforeJSON: Data?
    var afterJSON: Data?

    static func read(_ data: Data) -> DispatchExecutionResult {
        DispatchExecutionResult(
            data: data,
            targetEntity: nil,
            targetID: nil,
            beforeJSON: nil,
            afterJSON: nil
        )
    }
}
