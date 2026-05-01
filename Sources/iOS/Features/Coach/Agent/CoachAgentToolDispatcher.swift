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
    let auditStore: CoachAgentAuditStore
    let activeCutProvider: () -> ActiveCut?
    let onMutation: (() -> Void)?
    let nowProvider: () -> Date
    let calendar: Calendar

    init(
        repository: ReadingRepository,
        macroPlanStore: MacroPlanStore,
        macroDeviationStore: MacroDeviationStore,
        macroUntrackedRangeStore: MacroUntrackedRangeStore,
        auditStore: CoachAgentAuditStore,
        activeCutProvider: @escaping () -> ActiveCut? = { ActiveCutStore.load() },
        onMutation: (() -> Void)? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.macroPlanStore = macroPlanStore
        self.macroDeviationStore = macroDeviationStore
        self.macroUntrackedRangeStore = macroUntrackedRangeStore
        self.auditStore = auditStore
        self.activeCutProvider = activeCutProvider
        self.onMutation = onMutation
        self.nowProvider = nowProvider
        self.calendar = calendar
    }

    private static let decoder = JSONDecoder()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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
        return CoachSnapshotResult(
            activeCut: activeCut.map { CoachActiveCutDTO($0, now: now) },
            currentMacroPlan: currentPlan.map(CoachMacroPlanPeriodDTO.init),
            recentReadings: allReadings.filter { $0.date >= cutoff }.map(CoachReadingDTO.init),
            recentMacroDeviations: allDeviations.filter { $0.date >= cutoff }.map(CoachMacroDeviationDTO.init),
            recentUntrackedRanges: allRanges.filter { $0.endDate >= cutoff }.map(CoachUntrackedRangeDTO.init),
            recentSleep: allSleep.filter { $0.nightDate >= cutoff }.map(CoachSleepNightDTO.init),
            recentActivity: allActivity.filter { $0.day >= cutoff }.map(CoachDailyActivityDTO.init),
            recommendation: CoachRecommendationDTO(recommendation),
            generatedAt: now
        )
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
        case .replaceCurrentMacroPlan:
            let args = try decode(argsJSON, as: ReplaceCurrentMacroPlanArgs.self)
            return try replaceCurrentMacroPlan(args)
        case .logMacroDeviation:
            let args = try decode(argsJSON, as: LogMacroDeviationArgs.self)
            return try logMacroDeviation(args)
        case .markUntrackedRange:
            let args = try decode(argsJSON, as: MarkUntrackedRangeArgs.self)
            return try markUntrackedRange(args)
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
