import Foundation

indirect enum CoachAgentJSONSchema: Encodable, Sendable {
    case string(description: String? = nil, enumValues: [String]? = nil)
    case integer(description: String? = nil)
    case number(description: String? = nil)
    case boolean(description: String? = nil)
    case array(items: CoachAgentJSONSchema, description: String? = nil)
    case object(
        properties: [String: CoachAgentJSONSchema],
        required: [String] = [],
        additionalProperties: Bool = false,
        description: String? = nil
    )

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case items
        case properties
        case required
        case additionalProperties
        case enumValues = "enum"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let description, let enumValues):
            try c.encode("string", forKey: .type)
            if let description { try c.encode(description, forKey: .description) }
            if let enumValues { try c.encode(enumValues, forKey: .enumValues) }
        case .integer(let description):
            try c.encode("integer", forKey: .type)
            if let description { try c.encode(description, forKey: .description) }
        case .number(let description):
            try c.encode("number", forKey: .type)
            if let description { try c.encode(description, forKey: .description) }
        case .boolean(let description):
            try c.encode("boolean", forKey: .type)
            if let description { try c.encode(description, forKey: .description) }
        case .array(let items, let description):
            try c.encode("array", forKey: .type)
            try c.encode(items, forKey: .items)
            if let description { try c.encode(description, forKey: .description) }
        case .object(let properties, let required, let additionalProperties, let description):
            try c.encode("object", forKey: .type)
            try c.encode(properties, forKey: .properties)
            try c.encode(required, forKey: .required)
            try c.encode(additionalProperties, forKey: .additionalProperties)
            if let description { try c.encode(description, forKey: .description) }
        }
    }
}

struct CoachToolDefinition: Encodable, Sendable {
    var name: String
    var description: String
    var parameters: CoachAgentJSONSchema
}

private struct CoachToolEnvelope: Encodable {
    var type = "function"
    var function: CoachToolDefinition
}

enum CoachTool: String, CaseIterable, Sendable {
    static let schemaVersion = "coach-tools-v2"

    case getCoachSnapshot = "get_coach_snapshot"
    case listMacroPlanPeriods = "list_macro_plan_periods"
    case listMacroDeviations = "list_macro_deviations"
    case listUntrackedRanges = "list_untracked_ranges"
    case appendCoachNote = "append_coach_note"
    case recordMemory = "record_memory"
    case replaceCurrentMacroPlan = "replace_current_macro_plan"
    case logMacroDeviation = "log_macro_deviation"
    case markUntrackedRange = "mark_untracked_range"

    static var json: Data {
        let envelopes = allCases.map { CoachToolEnvelope(function: $0.definition) }
        return (try? JSONEncoder().encode(envelopes)) ?? Data("[]".utf8)
    }

    var definition: CoachToolDefinition {
        switch self {
        case .getCoachSnapshot:
            return .init(
                name: rawValue,
                description: "Read the active cut, current macro plan, recent logs, and a computed coach recommendation snapshot.",
                parameters: .object(
                    properties: [
                        "historyDays": .integer(description: "Recent days to include. Defaults to 21; max 90.")
                    ]
                )
            )
        case .listMacroPlanPeriods:
            return .init(
                name: rawValue,
                description: "Read macro plan periods for the active cut, oldest first.",
                parameters: .object(
                    properties: [
                        "cutStartDate": .string(description: "Optional yyyy-MM-dd cut start. Omit to use the active cut."),
                        "limit": .integer(description: "Optional maximum number of periods.")
                    ]
                )
            )
        case .listMacroDeviations:
            return .init(
                name: rawValue,
                description: "Read logged macro deviations for the active cut.",
                parameters: .object(
                    properties: [
                        "cutStartDate": .string(description: "Optional yyyy-MM-dd cut start. Omit to use the active cut."),
                        "fromDate": .string(description: "Optional yyyy-MM-dd lower bound."),
                        "toDate": .string(description: "Optional yyyy-MM-dd upper bound."),
                        "limit": .integer(description: "Optional maximum number of deviations.")
                    ]
                )
            )
        case .listUntrackedRanges:
            return .init(
                name: rawValue,
                description: "Read macro untracked ranges for the active cut.",
                parameters: .object(
                    properties: [
                        "cutStartDate": .string(description: "Optional yyyy-MM-dd cut start. Omit to use the active cut."),
                        "limit": .integer(description: "Optional maximum number of ranges.")
                    ]
                )
            )
        case .appendCoachNote:
            return .init(
                name: rawValue,
                description: "Append a coach note through the audit store. Use for user-provided context or factual observations.",
                parameters: .object(
                    properties: [
                        "text": .string(description: "Plain note text. No encouragement, praise, or moral judgment."),
                        "kind": .string(description: "Note kind.", enumValues: ["checkIn", "observation", "planReason", "foodContext", "trainingContext", "sleepContext", "moodContext", "digestionContext", "internalAudit"]),
                        "visibility": .string(description: "Visibility for the note.", enumValues: ["userVisible", "auditOnly"]),
                        "cutStartDate": .string(description: "Optional yyyy-MM-dd cut start. Omit to use the active cut."),
                        "day": .string(description: "Optional yyyy-MM-dd day the note refers to.")
                    ],
                    required: ["text"]
                )
            )
        case .recordMemory:
            return .init(
                name: rawValue,
                description: "Persist a durable factual memory that should be available in future coach agent prompts. Use sparingly for stable preferences, constraints, or recurring context.",
                parameters: .object(
                    properties: [
                        "text": .string(description: "Stable factual memory text, 1000 characters or fewer.")
                    ],
                    required: ["text"]
                )
            )
        case .replaceCurrentMacroPlan:
            return .init(
                name: rawValue,
                description: "Safely replace the active cut's current macro plan period.",
                parameters: .object(
                    properties: [
                        "cutStartDate": .string(description: "Optional yyyy-MM-dd cut start. Omit to use the active cut."),
                        "kcal": .integer(description: "Daily calories, 800 to 6000."),
                        "proteinG": .integer(description: "Daily protein grams. Omit if unknown."),
                        "fatG": .integer(description: "Daily fat grams. Omit if unknown."),
                        "carbsG": .integer(description: "Daily carbs grams. Omit if unknown."),
                        "tag": .string(description: "Plan tag.", enumValues: ["standard", "refeed", "dietBreak", "custom"]),
                        "customTagLabel": .string(description: "Required only when tag is custom."),
                        "note": .string(description: "Short factual reason for the change.")
                    ],
                    required: ["kcal"]
                )
            )
        case .logMacroDeviation:
            return .init(
                name: rawValue,
                description: "Log or update one day's macro adherence miss through the macro deviation store.",
                parameters: .object(
                    properties: [
                        "date": .string(description: "yyyy-MM-dd day to log."),
                        "cutStartDate": .string(description: "Optional yyyy-MM-dd cut start. Omit to use the active cut."),
                        "direction": .string(description: "Whether intake was over, under, or unknown.", enumValues: ["over", "under", "unknown"]),
                        "magnitude": .string(description: "Deviation size.", enumValues: ["slight", "moderate", "large", "wayOff"]),
                        "note": .string(description: "Optional factual note.")
                    ],
                    required: ["date", "direction", "magnitude"]
                )
            )
        case .markUntrackedRange:
            return .init(
                name: rawValue,
                description: "Mark a date range as intentionally untracked for macro adherence.",
                parameters: .object(
                    properties: [
                        "cutStartDate": .string(description: "Optional yyyy-MM-dd cut start. Omit to use the active cut."),
                        "startDate": .string(description: "yyyy-MM-dd range start."),
                        "endDate": .string(description: "yyyy-MM-dd range end, not in the future."),
                        "reason": .string(description: "Reason for untracked range.", enumValues: ["travel", "illness", "life", "custom"]),
                        "customReasonLabel": .string(description: "Required only when reason is custom.")
                    ],
                    required: ["startDate", "endDate", "reason"]
                )
            )
        }
    }
}

struct CoachSnapshotArgs: Decodable {
    var historyDays: Int?
}

struct CoachCutScopedArgs: Decodable {
    var cutStartDate: String?
    var limit: Int?
}

struct ListMacroDeviationsArgs: Decodable {
    var cutStartDate: String?
    var fromDate: String?
    var toDate: String?
    var limit: Int?
}

struct AppendCoachNoteArgs: Decodable {
    var text: String
    var kind: String?
    var visibility: String?
    var cutStartDate: String?
    var day: String?
}

struct RecordMemoryArgs: Decodable {
    var text: String
}

struct ReplaceCurrentMacroPlanArgs: Decodable {
    var cutStartDate: String?
    var kcal: Int
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var tag: String?
    var customTagLabel: String?
    var note: String?
}

struct LogMacroDeviationArgs: Decodable {
    var date: String
    var cutStartDate: String?
    var direction: String
    var magnitude: String
    var note: String?
}

struct MarkUntrackedRangeArgs: Decodable {
    var cutStartDate: String?
    var startDate: String
    var endDate: String
    var reason: String
    var customReasonLabel: String?
}

struct CoachSnapshotResult: Codable, Equatable, Sendable {
    var activeCut: CoachActiveCutDTO?
    var currentMacroPlan: CoachMacroPlanPeriodDTO?
    var recentReadings: [CoachReadingDTO]
    var recentMacroDeviations: [CoachMacroDeviationDTO]
    var recentUntrackedRanges: [CoachUntrackedRangeDTO]
    var recentSleep: [CoachSleepNightDTO]
    var recentActivity: [CoachDailyActivityDTO]
    var recommendation: CoachRecommendationDTO?
    var generatedAt: Date
}

struct CoachPlanPeriodsResult: Codable, Equatable, Sendable {
    var cutStartDate: Date
    var periods: [CoachMacroPlanPeriodDTO]
}

struct CoachMacroDeviationsResult: Codable, Equatable, Sendable {
    var cutStartDate: Date
    var deviations: [CoachMacroDeviationDTO]
}

struct CoachUntrackedRangesResult: Codable, Equatable, Sendable {
    var cutStartDate: Date
    var ranges: [CoachUntrackedRangeDTO]
}

struct CoachNoteMutationResult: Codable, Equatable, Sendable {
    var id: UUID
    var runID: UUID
    var text: String
    var kind: String
    var visibility: String
    var cutStartDate: Date?
    var day: Date?
}

struct CoachMemoryMutationResult: Codable, Equatable, Sendable {
    var memory: CoachAgentMemory
}

struct CoachMacroPlanMutationResult: Codable, Equatable, Sendable {
    var period: CoachMacroPlanPeriodDTO
}

struct CoachMacroDeviationMutationResult: Codable, Equatable, Sendable {
    var deviation: CoachMacroDeviationDTO
}

struct CoachUntrackedRangeMutationResult: Codable, Equatable, Sendable {
    var range: CoachUntrackedRangeDTO
}

struct CoachActiveCutDTO: Codable, Equatable, Sendable {
    var startDate: Date
    var targetEndDate: Date
    var startWeightKg: Double
    var targetWeightKg: Double
    var totalLossKg: Double
    var daysElapsed: Int
    var daysRemaining: Int

    init(_ cut: ActiveCut, now: Date) {
        startDate = cut.startDate
        targetEndDate = cut.targetEndDate
        startWeightKg = cut.startWeightKg
        targetWeightKg = cut.targetWeightKg
        totalLossKg = cut.totalLossKg
        daysElapsed = cut.daysElapsed(now: now)
        daysRemaining = cut.daysRemaining(now: now)
    }
}

struct CoachMacroPlanPeriodDTO: Codable, Equatable, Sendable {
    var id: UUID
    var cutStartDate: Date
    var startDate: Date
    var endDate: Date?
    var kcal: Int
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var tag: String
    var customTagLabel: String?
    var note: String?
    var createdAt: Date

    init(_ period: MacroPlanPeriod) {
        id = period.id
        cutStartDate = period.cutStartDate
        startDate = period.startDate
        endDate = period.endDate
        kcal = period.kcal
        proteinG = period.proteinG
        fatG = period.fatG
        carbsG = period.carbsG
        tag = period.tag.rawValue
        customTagLabel = period.customTagLabel
        note = period.note
        createdAt = period.createdAt
    }
}

struct CoachMacroDeviationDTO: Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var cutStartDate: Date
    var planPeriodId: UUID
    var direction: String
    var magnitude: String
    var note: String?
    var loggedAt: Date

    init(_ deviation: MacroDeviation) {
        id = deviation.id
        date = deviation.date
        cutStartDate = deviation.cutStartDate
        planPeriodId = deviation.planPeriodId
        direction = deviation.direction.rawValue
        magnitude = deviation.magnitude.rawValue
        note = deviation.note
        loggedAt = deviation.loggedAt
    }
}

struct CoachUntrackedRangeDTO: Codable, Equatable, Sendable {
    var id: UUID
    var cutStartDate: Date
    var startDate: Date
    var endDate: Date
    var reason: String
    var customReasonLabel: String?
    var createdAt: Date

    init(_ range: MacroUntrackedRange) {
        id = range.id
        cutStartDate = range.cutStartDate
        startDate = range.startDate
        endDate = range.endDate
        reason = range.reason.rawValue
        customReasonLabel = range.customReasonLabel
        createdAt = range.createdAt
    }
}

struct CoachReadingDTO: Codable, Equatable, Sendable {
    var date: Date
    var weightKg: Double
    var waistCm: Double?
    var hipsCm: Double?
    var note: String?

    init(_ reading: Reading) {
        date = reading.date
        weightKg = reading.weightKg
        waistCm = reading.waistCm
        hipsCm = reading.hipsCm
        note = reading.note
    }
}

struct CoachSleepNightDTO: Codable, Equatable, Sendable {
    var nightDate: Date
    var asleepMinutes: Int

    init(_ night: SleepNight) {
        nightDate = night.nightDate
        asleepMinutes = night.asleepMinutes
    }
}

struct CoachDailyActivityDTO: Codable, Equatable, Sendable {
    var day: Date
    var steps: Int
    var activeEnergyKcal: Double?
    var exerciseMinutes: Int?

    init(_ activity: DailyActivity) {
        day = activity.day
        steps = activity.steps
        activeEnergyKcal = activity.activeEnergyKcal
        exerciseMinutes = activity.exerciseMinutes
    }
}

struct CoachRecommendationDTO: Codable, Equatable, Sendable {
    var decision: String
    var dailyTargets: CoachTargetsDTO?
    var weeklyTargets: CoachTargetsDTO?
    var reasons: [CoachReasonDTO]
    var prompt: String?
    var analysis: CoachAnalysisDTO

    init(_ recommendation: CutCoachRecommendation) {
        decision = recommendation.decision.rawValue
        dailyTargets = recommendation.dailyTargets.map(CoachTargetsDTO.init)
        weeklyTargets = recommendation.weeklyTargets.map(CoachTargetsDTO.init)
        reasons = recommendation.reasons.map(CoachReasonDTO.init)
        prompt = recommendation.prompt?.rawValue
        analysis = CoachAnalysisDTO(recommendation.analysis)
    }
}

struct CoachReasonDTO: Codable, Equatable, Sendable {
    var code: String
    var text: String

    init(_ reason: CutCoachReason) {
        code = reason.code.rawValue
        text = reason.text
    }
}

struct CoachTargetsDTO: Codable, Equatable, Sendable {
    var kcal: Int
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var training: CoachTrainingTargetDTO

    init(_ targets: CutCoachTargets) {
        kcal = targets.kcal
        proteinG = targets.proteinG
        fatG = targets.fatG
        carbsG = targets.carbsG
        training = CoachTrainingTargetDTO(targets.training)
    }
}

struct CoachTrainingTargetDTO: Codable, Equatable, Sendable {
    var steps: Int?
    var exerciseMinutes: Int?

    init(_ target: TrainingTarget) {
        steps = target.steps
        exerciseMinutes = target.exerciseMinutes
    }
}

struct CoachAnalysisDTO: Codable, Equatable, Sendable {
    var observedLossKgPerWeek: Double?
    var targetLossKgPerWeek: Double?
    var sevenDayLoggedMisses: Int
    var sevenDayUntrackedDays: Int
    var recentSleepHours: Double?
    var baselineSleepHours: Double?
    var recentSteps: Int?
    var baselineSteps: Int?

    init(_ analysis: CutCoachAnalysis) {
        observedLossKgPerWeek = analysis.observedLossKgPerWeek
        targetLossKgPerWeek = analysis.targetLossKgPerWeek
        sevenDayLoggedMisses = analysis.sevenDayLoggedMisses
        sevenDayUntrackedDays = analysis.sevenDayUntrackedDays
        recentSleepHours = analysis.recentSleepHours
        baselineSleepHours = analysis.baselineSleepHours
        recentSteps = analysis.recentSteps
        baselineSteps = analysis.baselineSteps
    }
}
