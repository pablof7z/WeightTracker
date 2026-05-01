import Foundation

public struct CutCoachTargets: Equatable, Sendable {
    public var kcal: Int
    public var proteinG: Int?
    public var carbsG: Int?
    public var fatG: Int?
    public var training: TrainingTarget

    public init(
        kcal: Int,
        proteinG: Int? = nil,
        carbsG: Int? = nil,
        fatG: Int? = nil,
        training: TrainingTarget = .init()
    ) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.training = training
    }
}

public struct TrainingTarget: Equatable, Sendable {
    public var steps: Int?
    public var exerciseMinutes: Int?

    public init(steps: Int? = nil, exerciseMinutes: Int? = nil) {
        self.steps = steps
        self.exerciseMinutes = exerciseMinutes
    }
}

public struct CutCoachReason: Equatable, Sendable {
    public enum Code: String, Codable, CaseIterable, Sendable {
        case trendBelowTarget
        case trendAboveTarget
        case trendOnTarget
        case sleepBelowBaseline
        case stepsBelowBaseline
        case loggedMisses
        case untrackedDays
        case insufficientWeightData
        case insufficientFoodData
        case insufficientSleepData
        case insufficientActivityData
        case calorieGuardrail
        case baselinePlan
        case noActiveCut
        case missingMacroPlan
    }

    public var code: Code
    public var text: String

    public init(_ code: Code, _ text: String) {
        self.code = code
        self.text = text
    }
}

public enum CutCoachDecision: String, Codable, CaseIterable, Sendable {
    case holdTargets
    case lowerCalories
    case raiseCalories
    case requestData
    case noActiveCut
}

public enum CutCoachPrompt: String, Codable, CaseIterable, Sendable {
    case bodyWeight
    case macroDeviation
    case sleep
    case steps
    case macroPlan

    public var title: String {
        switch self {
        case .bodyWeight: return "Log body weight"
        case .macroDeviation: return "Log food adherence"
        case .sleep: return "Add sleep"
        case .steps: return "Add steps"
        case .macroPlan: return "Set macro plan"
        }
    }
}

public struct CutCoachRecommendation: Equatable, Sendable {
    public var decision: CutCoachDecision
    public var dailyTargets: CutCoachTargets?
    public var weeklyTargets: CutCoachTargets?
    public var reasons: [CutCoachReason]
    public var prompt: CutCoachPrompt?
    public var analysis: CutCoachAnalysis

    public init(
        decision: CutCoachDecision,
        dailyTargets: CutCoachTargets?,
        weeklyTargets: CutCoachTargets?,
        reasons: [CutCoachReason],
        prompt: CutCoachPrompt?,
        analysis: CutCoachAnalysis = .init()
    ) {
        self.decision = decision
        self.dailyTargets = dailyTargets
        self.weeklyTargets = weeklyTargets
        self.reasons = reasons
        self.prompt = prompt
        self.analysis = analysis
    }
}

public struct CutCoachAnalysis: Equatable, Sendable {
    public var observedLossKgPerWeek: Double?
    public var targetLossKgPerWeek: Double?
    public var sevenDayLoggedMisses: Int
    public var sevenDayUntrackedDays: Int
    public var recentSleepHours: Double?
    public var baselineSleepHours: Double?
    public var recentSteps: Int?
    public var baselineSteps: Int?

    public init(
        observedLossKgPerWeek: Double? = nil,
        targetLossKgPerWeek: Double? = nil,
        sevenDayLoggedMisses: Int = 0,
        sevenDayUntrackedDays: Int = 0,
        recentSleepHours: Double? = nil,
        baselineSleepHours: Double? = nil,
        recentSteps: Int? = nil,
        baselineSteps: Int? = nil
    ) {
        self.observedLossKgPerWeek = observedLossKgPerWeek
        self.targetLossKgPerWeek = targetLossKgPerWeek
        self.sevenDayLoggedMisses = sevenDayLoggedMisses
        self.sevenDayUntrackedDays = sevenDayUntrackedDays
        self.recentSleepHours = recentSleepHours
        self.baselineSleepHours = baselineSleepHours
        self.recentSteps = recentSteps
        self.baselineSteps = baselineSteps
    }
}

public struct CutCoachContext: Sendable {
    public var activeCut: ActiveCut?
    public var planPeriod: CutCoachMacroPlan?
    public var readings: [CutCoachReading]
    public var macroDeviations: [CutCoachMacroDeviation]
    public var untrackedRanges: [CutCoachUntrackedRange]
    public var sleepNights: [CutCoachSleepNight]
    public var dailyActivities: [CutCoachDailyActivity]
    public var now: Date
    public var calendar: Calendar

    public init(
        activeCut: ActiveCut?,
        planPeriod: CutCoachMacroPlan?,
        readings: [CutCoachReading] = [],
        macroDeviations: [CutCoachMacroDeviation] = [],
        untrackedRanges: [CutCoachUntrackedRange] = [],
        sleepNights: [CutCoachSleepNight] = [],
        dailyActivities: [CutCoachDailyActivity] = [],
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.activeCut = activeCut
        self.planPeriod = planPeriod
        self.readings = readings
        self.macroDeviations = macroDeviations
        self.untrackedRanges = untrackedRanges
        self.sleepNights = sleepNights
        self.dailyActivities = dailyActivities
        self.now = now
        self.calendar = calendar
    }
}

public struct CutCoachReading: Equatable, Sendable {
    public var date: Date
    public var weightKg: Double
    public var waistCm: Double?
    public var hipsCm: Double?
    public var note: String?

    public init(date: Date, weightKg: Double, waistCm: Double? = nil, hipsCm: Double? = nil, note: String? = nil) {
        self.date = date
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.hipsCm = hipsCm
        self.note = note
    }

    public init(_ reading: Reading) {
        self.init(
            date: reading.date,
            weightKg: reading.weightKg,
            waistCm: reading.waistCm,
            hipsCm: reading.hipsCm,
            note: reading.note
        )
    }
}

public struct CutCoachMacroPlan: Equatable, Sendable {
    public var startDate: Date
    public var endDate: Date?
    public var kcal: Int
    public var proteinG: Int?
    public var carbsG: Int?
    public var fatG: Int?
    public var tag: MacroPlanTag

    public init(
        startDate: Date,
        endDate: Date? = nil,
        kcal: Int,
        proteinG: Int? = nil,
        carbsG: Int? = nil,
        fatG: Int? = nil,
        tag: MacroPlanTag = .standard
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.tag = tag
    }

    public init(_ period: MacroPlanPeriod) {
        self.init(
            startDate: period.startDate,
            endDate: period.endDate,
            kcal: period.kcal,
            proteinG: period.proteinG,
            carbsG: period.carbsG,
            fatG: period.fatG,
            tag: period.tag
        )
    }
}

public struct CutCoachMacroDeviation: Equatable, Sendable {
    public var date: Date
    public var direction: MacroDirection
    public var magnitude: MacroMagnitude

    public init(date: Date, direction: MacroDirection, magnitude: MacroMagnitude) {
        self.date = date
        self.direction = direction
        self.magnitude = magnitude
    }

    public init(_ deviation: MacroDeviation) {
        self.init(date: deviation.date, direction: deviation.direction, magnitude: deviation.magnitude)
    }
}

public struct CutCoachUntrackedRange: Equatable, Sendable {
    public var startDate: Date
    public var endDate: Date
    public var reason: UntrackedReason

    public init(startDate: Date, endDate: Date, reason: UntrackedReason = .life) {
        self.startDate = startDate
        self.endDate = endDate
        self.reason = reason
    }

    public init(_ range: MacroUntrackedRange) {
        self.init(startDate: range.startDate, endDate: range.endDate, reason: range.reason)
    }
}

public struct CutCoachSleepNight: Equatable, Sendable {
    public var nightDate: Date
    public var asleepMinutes: Int

    public init(nightDate: Date, asleepMinutes: Int) {
        self.nightDate = nightDate
        self.asleepMinutes = max(0, asleepMinutes)
    }

    public init(_ night: SleepNight) {
        self.init(nightDate: night.nightDate, asleepMinutes: night.asleepMinutes)
    }
}

public struct CutCoachDailyActivity: Equatable, Sendable {
    public var day: Date
    public var steps: Int
    public var activeEnergyKcal: Double?
    public var exerciseMinutes: Int?

    public init(day: Date, steps: Int, activeEnergyKcal: Double? = nil, exerciseMinutes: Int? = nil) {
        self.day = day
        self.steps = max(0, steps)
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
    }

    public init(_ activity: DailyActivity) {
        self.init(
            day: activity.day,
            steps: activity.steps,
            activeEnergyKcal: activity.activeEnergyKcal,
            exerciseMinutes: activity.exerciseMinutes
        )
    }
}
