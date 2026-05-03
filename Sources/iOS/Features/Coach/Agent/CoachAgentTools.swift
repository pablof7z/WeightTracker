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
    static let schemaVersion = "coach-tools-v5"

    case getCoachSnapshot = "get_coach_snapshot"
    case listMacroPlanPeriods = "list_macro_plan_periods"
    case listMacroDeviations = "list_macro_deviations"
    case listUntrackedRanges = "list_untracked_ranges"
    case appendCoachNote = "append_coach_note"
    case recordMemory = "record_memory"
    case replaceCurrentMacroPlan = "replace_current_macro_plan"
    case logMacroDeviation = "log_macro_deviation"
    case markUntrackedRange = "mark_untracked_range"
    case getMealSchedule = "get_meal_schedule"
    case replaceCurrentMealSchedule = "replace_current_meal_schedule"
    case logMealEvent = "log_meal_event"
    case calculateMeal = "calculate_meal"
    case scheduleNudge = "schedule_nudge"
    case cancelNudge = "cancel_nudge"
    case setStepTarget = "set_step_target"
    case scheduleDietBreak = "schedule_diet_break"
    case scheduleRefeed = "schedule_refeed"
    case proposeMealPlan = "propose_meal_plan"

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
        case .getMealSchedule:
            return .init(
                name: rawValue,
                description: "Read the user's current meal schedule, recent meal events, and timing pattern statistics for the active cut.",
                parameters: .object(
                    properties: [
                        "cutStartDate": .string(description: "Optional yyyy-MM-dd cut start. Omit to use the active cut."),
                        "historyDays": .integer(description: "Recent days of meal events to include. Defaults to 14; max 90.")
                    ]
                )
            )
        case .replaceCurrentMealSchedule:
            return .init(
                name: rawValue,
                description: "Safely replace the active cut's current meal schedule. Only call after the user has explicitly accepted a proposed change in natural language.",
                parameters: .object(
                    properties: [
                        "cutStartDate": .string(description: "Optional yyyy-MM-dd cut start. Omit to use the active cut."),
                        "note": .string(description: "Optional short factual note explaining the change."),
                        "slots": .array(
                            items: .object(
                                properties: [
                                    "name": .string(description: "Meal name shown to the user, e.g. \"Breakfast\"."),
                                    "time": .string(description: "Local time in HH:mm 24-hour format."),
                                    "kind": .string(
                                        description: "Optional meal kind tag.",
                                        enumValues: ["breakfast", "lunch", "dinner", "snack", "preWorkout", "postWorkout", "custom"]
                                    ),
                                    "kcalPercent": .number(description: "Optional fraction 0-1 of daily calories for this meal."),
                                    "proteinPercent": .number(description: "Optional fraction 0-1 of daily protein for this meal."),
                                    "fatPercent": .number(description: "Optional fraction 0-1 of daily fat for this meal."),
                                    "carbsPercent": .number(description: "Optional fraction 0-1 of daily carbs for this meal."),
                                    "kcal": .integer(description: "Optional absolute kcal for this meal (use the value from calculate_meal). Takes priority over kcalPercent."),
                                    "proteinG": .integer(description: "Optional absolute protein grams for this meal (from calculate_meal)."),
                                    "fatG": .integer(description: "Optional absolute fat grams for this meal (from calculate_meal)."),
                                    "carbsG": .integer(description: "Optional absolute carbs grams for this meal (from calculate_meal)."),
                                    "foodDescription": .string(description: "Optional human-readable food summary, e.g. \"150g chicken + 200g rice\".")
                                ],
                                required: ["name", "time"]
                            ),
                            description: "Ordered list of meal slots, between 1 and 12 entries with monotonically increasing times."
                        )
                    ],
                    required: ["slots"]
                )
            )
        case .logMealEvent:
            return .init(
                name: rawValue,
                description: "Log a single meal event reported by the user (eaten, skipped, or partial). One call per meal.",
                parameters: .object(
                    properties: [
                        "date": .string(description: "yyyy-MM-dd day the meal happened. Cannot be in the future, max 7 days back."),
                        "mealName": .string(description: "Meal slot name, matched case-insensitively against the active schedule."),
                        "status": .string(description: "Whether the meal was eaten, skipped, or partially eaten.", enumValues: ["eaten", "skipped", "partial"]),
                        "capturedFrom": .string(description: "Source of the report.", enumValues: ["tap", "voice", "agent"]),
                        "ateAt": .string(description: "Optional HH:mm local time the meal was eaten. Required when status is eaten or partial unless timeQuality is unknown. Must be omitted when status is skipped."),
                        "timeQuality": .string(description: "Confidence in the ateAt time.", enumValues: ["exact", "approximate", "unknown"]),
                        "hungerBefore": .string(description: "Optional hunger level just before eating.", enumValues: ["low", "moderate", "high"]),
                        "hungerAfter": .string(description: "Optional hunger level shortly after eating.", enumValues: ["low", "moderate", "high"]),
                        "note": .string(description: "Optional short factual note.")
                    ],
                    required: ["date", "mealName", "status", "capturedFrom", "timeQuality"]
                )
            )
        case .calculateMeal:
            return .init(
                name: rawValue,
                description: "Calculate nutrition (kcal, protein, fat, carbs) for a list of food items. Each item is a natural language description like '150g raw chicken breast' or '1 cup cooked basmati rice'. Returns per-item and total macros. This tool only COMPUTES — it does not log or store anything. After getting results, use replace_current_meal_schedule to update slot macros, or log_meal_event to record the meal.",
                parameters: .object(
                    properties: [
                        "items": .array(
                            items: .string(description: "Natural-language food item, e.g. '150g raw chicken breast' or '1 cup cooked basmati rice'."),
                            description: "Between 1 and 20 food descriptions to price for one meal."
                        ),
                        "mealName": .string(description: "Optional meal slot name this calculation is for (audit only — the tool does not write to the slot)."),
                        "assumeRawWhenAmbiguous": .boolean(description: "When true (default), unspecified weights are treated as raw rather than cooked.")
                    ],
                    required: ["items"]
                )
            )
        case .scheduleNudge:
            return .init(
                name: rawValue,
                description: "Schedule a proactive notification nudge to fire at a specific time or relative delay. Use this after check-ins to set watchers for missed meals, step shortfalls, or follow-up reminders. The coach plants these during sessions — they fire later without user action.",
                parameters: .object(
                    properties: [
                        "message": .string(description: "Exact notification text, first-person, actionable in under 30 seconds."),
                        "scheduledAt": .string(description: "ISO-8601 datetime when the nudge should fire."),
                        "expiresAt": .string(description: "Optional ISO-8601 datetime after which the nudge is irrelevant even if not fired.")
                    ],
                    required: ["message", "scheduledAt"]
                )
            )
        case .cancelNudge:
            return .init(
                name: rawValue,
                description: "Cancel a previously scheduled nudge by its ID. Use when context changes (user travels, illness, plan change makes the nudge moot).",
                parameters: .object(
                    properties: [
                        "nudgeId": .string(description: "UUID string of the nudge to cancel.")
                    ],
                    required: ["nudgeId"]
                )
            )
        case .setStepTarget:
            return .init(
                name: rawValue,
                description: "Set the user's daily step target. Stored as part of the active cut's plan. Use when establishing initial activity targets or adjusting based on observed performance.",
                parameters: .object(
                    properties: [
                        "dailySteps": .integer(description: "Target step count per day, between 2000 and 20000."),
                        "rationale": .string(description: "Optional brief factual reason for the target.")
                    ],
                    required: ["dailySteps"]
                )
            )
        case .scheduleDietBreak:
            return .init(
                name: rawValue,
                description: "Schedule a diet break at maintenance calories, starting today or on a future date. Creates a new macro plan period with the dietBreak tag and duration. The coach uses this after detecting prolonged deficit without progress.",
                parameters: .object(
                    properties: [
                        "durationDays": .integer(description: "Length of the break, 7 to 21."),
                        "kcal": .integer(description: "Maintenance calories during the break."),
                        "proteinG": .integer(description: "Optional protein target during break (default: same as cut target)."),
                        "startDate": .string(description: "Optional yyyy-MM-dd start date, defaults to today."),
                        "note": .string(description: "Optional reason for the break.")
                    ],
                    required: ["durationDays", "kcal"]
                )
            )
        case .scheduleRefeed:
            return .init(
                name: rawValue,
                description: "Schedule a single-day carbohydrate refeed. Creates a new macro plan period with the refeed tag for one day, then returns to the prior plan. Use this as a lighter intervention before a full diet break.",
                parameters: .object(
                    properties: [
                        "kcal": .integer(description: "Refeed day calories (typically 15-20% above deficit)."),
                        "carbsG": .integer(description: "Carbs target for the refeed day (majority of extra calories)."),
                        "proteinG": .integer(description: "Optional protein target (default: same as cut)."),
                        "fatG": .integer(description: "Optional fat target (keep low on refeed — carbs are the lever)."),
                        "note": .string(description: "Optional reason.")
                    ],
                    required: ["kcal", "carbsG"]
                )
            )
        case .proposeMealPlan:
            return .init(
                name: rawValue,
                description: "Generate 2-3 concrete food combinations for a meal slot given macro targets and preferences. Returns food items with grams and computed macros. Call this when setting up meal slots, after the user asks 'what should I eat', or when proposing substitutions. Always verify with the returned macros before presenting.",
                parameters: .object(
                    properties: [
                        "mealName": .string(description: "Slot name, e.g. \"Lunch\"."),
                        "targetKcal": .integer(description: "Calorie target for this meal."),
                        "targetProteinG": .integer(description: "Protein target in grams."),
                        "targetFatG": .integer(description: "Optional fat target in grams."),
                        "targetCarbsG": .integer(description: "Optional carbs target in grams."),
                        "preferences": .array(
                            items: .string(description: "Food preference or dietary style."),
                            description: "Optional foods the user likes or dietary style (e.g. \"high volume\", \"Mediterranean\")."
                        ),
                        "excludes": .array(
                            items: .string(description: "Food to exclude."),
                            description: "Optional foods to exclude (allergies, dislikes)."
                        )
                    ],
                    required: ["mealName", "targetKcal", "targetProteinG"]
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

struct GetMealScheduleArgs: Decodable {
    var cutStartDate: String?
    var historyDays: Int?
}

struct MealSlotArg: Decodable {
    var name: String
    var time: String
    var kind: String?
    var kcalPercent: Double?
    var proteinPercent: Double?
    var fatPercent: Double?
    var carbsPercent: Double?
    // Absolute macros, optionally produced by `calculate_meal`. When supplied,
    // these take priority over the percent-based fields when the UI resolves
    // per-meal nutrition.
    var kcal: Int?
    var proteinG: Int?
    var fatG: Int?
    var carbsG: Int?
    var foodDescription: String?
}

struct ReplaceCurrentMealScheduleArgs: Decodable {
    var cutStartDate: String?
    var note: String?
    var slots: [MealSlotArg]
}

struct LogMealEventArgs: Decodable {
    var date: String
    var mealName: String
    var status: String
    var capturedFrom: String
    var ateAt: String?
    var timeQuality: String
    var hungerBefore: String?
    var hungerAfter: String?
    var note: String?
}

struct CalculateMealArgs: Decodable {
    var items: [String]
    var mealName: String?
    var assumeRawWhenAmbiguous: Bool?
}

struct ScheduleNudgeArgs: Decodable {
    var message: String
    var scheduledAt: String
    var expiresAt: String?
}

struct CancelNudgeArgs: Decodable {
    var nudgeId: String
}

struct SetStepTargetArgs: Decodable {
    var dailySteps: Int
    var rationale: String?
}

struct ScheduleDietBreakArgs: Decodable {
    var durationDays: Int
    var kcal: Int
    var proteinG: Int?
    var startDate: String?
    var note: String?
}

struct ScheduleRefeedArgs: Decodable {
    var kcal: Int
    var carbsG: Int
    var proteinG: Int?
    var fatG: Int?
    var note: String?
}

struct ProposeMealPlanArgs: Decodable {
    var mealName: String
    var targetKcal: Int
    var targetProteinG: Int
    var targetFatG: Int?
    var targetCarbsG: Int?
    var preferences: [String]?
    var excludes: [String]?
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
    var currentMealSchedule: CoachMealScheduleDTO?
    var recentMealEvents: [CoachMealEventDTO]
    var mealStats: CoachMealStatsDTO?
    var generatedAt: Date

    init(
        activeCut: CoachActiveCutDTO?,
        currentMacroPlan: CoachMacroPlanPeriodDTO?,
        recentReadings: [CoachReadingDTO],
        recentMacroDeviations: [CoachMacroDeviationDTO],
        recentUntrackedRanges: [CoachUntrackedRangeDTO],
        recentSleep: [CoachSleepNightDTO],
        recentActivity: [CoachDailyActivityDTO],
        recommendation: CoachRecommendationDTO?,
        currentMealSchedule: CoachMealScheduleDTO? = nil,
        recentMealEvents: [CoachMealEventDTO] = [],
        mealStats: CoachMealStatsDTO? = nil,
        generatedAt: Date
    ) {
        self.activeCut = activeCut
        self.currentMacroPlan = currentMacroPlan
        self.recentReadings = recentReadings
        self.recentMacroDeviations = recentMacroDeviations
        self.recentUntrackedRanges = recentUntrackedRanges
        self.recentSleep = recentSleep
        self.recentActivity = recentActivity
        self.recommendation = recommendation
        self.currentMealSchedule = currentMealSchedule
        self.recentMealEvents = recentMealEvents
        self.mealStats = mealStats
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case activeCut, currentMacroPlan, recentReadings, recentMacroDeviations
        case recentUntrackedRanges, recentSleep, recentActivity, recommendation
        case currentMealSchedule, recentMealEvents, mealStats, generatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeCut = try c.decodeIfPresent(CoachActiveCutDTO.self, forKey: .activeCut)
        currentMacroPlan = try c.decodeIfPresent(CoachMacroPlanPeriodDTO.self, forKey: .currentMacroPlan)
        recentReadings = try c.decodeIfPresent([CoachReadingDTO].self, forKey: .recentReadings) ?? []
        recentMacroDeviations = try c.decodeIfPresent([CoachMacroDeviationDTO].self, forKey: .recentMacroDeviations) ?? []
        recentUntrackedRanges = try c.decodeIfPresent([CoachUntrackedRangeDTO].self, forKey: .recentUntrackedRanges) ?? []
        recentSleep = try c.decodeIfPresent([CoachSleepNightDTO].self, forKey: .recentSleep) ?? []
        recentActivity = try c.decodeIfPresent([CoachDailyActivityDTO].self, forKey: .recentActivity) ?? []
        recommendation = try c.decodeIfPresent(CoachRecommendationDTO.self, forKey: .recommendation)
        currentMealSchedule = try c.decodeIfPresent(CoachMealScheduleDTO.self, forKey: .currentMealSchedule)
        recentMealEvents = try c.decodeIfPresent([CoachMealEventDTO].self, forKey: .recentMealEvents) ?? []
        mealStats = try c.decodeIfPresent(CoachMealStatsDTO.self, forKey: .mealStats)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
    }
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

// MARK: - Meal scheduling DTOs

struct CoachMealSlotDTO: Codable, Equatable, Sendable {
    var id: UUID
    var scheduleId: UUID
    var name: String
    var minutesFromMidnight: Int
    var kind: String
    var sortOrder: Int
    var kcalPercent: Double?
    var proteinPercent: Double?
    var fatPercent: Double?
    var carbsPercent: Double?
    var note: String?

    init(_ slot: MealSlot) {
        id = slot.id
        scheduleId = slot.scheduleId
        name = slot.name
        minutesFromMidnight = slot.minutesFromMidnight
        kind = slot.kindRaw
        sortOrder = slot.sortOrder
        kcalPercent = slot.kcalPercent
        proteinPercent = slot.proteinPercent
        fatPercent = slot.fatPercent
        carbsPercent = slot.carbsPercent
        note = slot.note
    }
}

struct CoachMealScheduleDTO: Codable, Equatable, Sendable {
    var id: UUID
    var cutStartDate: Date
    var startDate: Date
    var endDate: Date?
    var note: String?
    var createdAt: Date
    var slots: [CoachMealSlotDTO]

    init(_ period: MealSchedulePeriod, slots: [MealSlot]) {
        id = period.id
        cutStartDate = period.cutStartDate
        startDate = period.startDate
        endDate = period.endDate
        note = period.note
        createdAt = period.createdAt
        self.slots = slots.map(CoachMealSlotDTO.init)
    }
}

struct CoachMealEventDTO: Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var loggedAt: Date
    var ateAt: Date
    var minutesFromMidnight: Int
    var scheduleId: UUID?
    var slotId: UUID?
    var slotNameSnapshot: String?
    var status: String
    var hungerBefore: String?
    var hungerAfter: String?
    var note: String?

    init(_ event: MealEvent) {
        id = event.id
        date = event.date
        loggedAt = event.loggedAt
        ateAt = event.ateAt
        minutesFromMidnight = event.minutesFromMidnight
        scheduleId = event.scheduleId
        slotId = event.slotId
        slotNameSnapshot = event.slotNameSnapshot
        status = event.statusRaw
        hungerBefore = event.hungerBeforeRaw
        hungerAfter = event.hungerAfterRaw
        note = event.note
    }
}

struct CoachMealStatPerMealDTO: Codable, Equatable, Sendable {
    var slotName: String
    var scheduledMinutes: Int
    var loggedCount: Int
    var skippedCount: Int
    var skipRate: Double
    var medianDelayMinutes: Int?
    var lateCount: Int
}

struct CoachMealStatsDTO: Codable, Equatable, Sendable {
    var windowDays: Int
    var perMeal: [CoachMealStatPerMealDTO]
    var overallSkipRate: Double
}

struct CoachMealScheduleResult: Codable, Equatable, Sendable {
    var schedule: CoachMealScheduleDTO?
    var recentEvents: [CoachMealEventDTO]
    var stats: CoachMealStatsDTO?
    var generatedAt: Date
}

struct CoachMealScheduleMutationResult: Codable, Equatable, Sendable {
    var schedule: CoachMealScheduleDTO
}

struct CoachMealEventMutationResult: Codable, Equatable, Sendable {
    var event: CoachMealEventDTO
}

// MARK: - Calculate-meal DTOs

struct CoachCalculatedFoodItemDTO: Codable, Equatable, Sendable {
    var input: String
    var food: String
    var fdcId: Int?
    var dataType: String?
    var grams: Double
    var rawEquivalentGrams: Double
    var state: String
    var stateAdjustment: CoachCookingAdjustmentDTO?
    var kcal: Int
    var proteinG: Double
    var fatG: Double
    var carbsG: Double
    var confidence: String
    var source: String
    var warnings: [String]

    init(_ item: CalculatedFoodItem) {
        input = item.input
        food = item.food
        fdcId = item.fdcId
        dataType = item.dataType
        grams = item.grams
        rawEquivalentGrams = item.rawEquivalentGrams
        state = item.state
        stateAdjustment = item.stateAdjustment.map(CoachCookingAdjustmentDTO.init)
        kcal = item.kcal
        proteinG = item.proteinG
        fatG = item.fatG
        carbsG = item.carbsG
        confidence = item.confidence
        source = item.source
        warnings = item.warnings
    }
}

struct CoachCookingAdjustmentDTO: Codable, Equatable, Sendable {
    var fromState: String
    var toState: String
    var factor: Double
    var rule: String

    init(_ info: CookingAdjustmentInfo) {
        fromState = info.fromState
        toState = info.toState
        factor = info.factor
        rule = info.rule
    }
}

struct CoachMacroTotalsDTO: Codable, Equatable, Sendable {
    var kcal: Int
    var proteinG: Double
    var fatG: Double
    var carbsG: Double

    init(_ totals: MacroTotals) {
        kcal = totals.kcal
        proteinG = totals.proteinG
        fatG = totals.fatG
        carbsG = totals.carbsG
    }
}

struct CoachCalculateMealResult: Codable, Equatable, Sendable {
    var items: [CoachCalculatedFoodItemDTO]
    var total: CoachMacroTotalsDTO
    var warnings: [String]
    var mealName: String?
    var schemaVersion: String

    init(from result: CalculateMealResult, mealName: String?) {
        items = result.items.map(CoachCalculatedFoodItemDTO.init)
        total = CoachMacroTotalsDTO(result.total)
        warnings = result.warnings
        self.mealName = mealName
        schemaVersion = result.schemaVersion
    }
}
