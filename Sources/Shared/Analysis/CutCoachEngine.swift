import Foundation

public enum CutCoachEngine {
    public static func evaluate(context: CutCoachContext) -> CutCoachRecommendation {
        guard let active = context.activeCut else {
            return CutCoachRecommendation(
                decision: .noActiveCut,
                dailyTargets: nil,
                weeklyTargets: nil,
                reasons: [.init(.noActiveCut, "no active cut")],
                prompt: nil
            )
        }

        guard let plan = context.planPeriod else {
            return CutCoachRecommendation(
                decision: .requestData,
                dailyTargets: nil,
                weeklyTargets: nil,
                reasons: [.init(.missingMacroPlan, "missing macro plan")],
                prompt: .macroPlan
            )
        }

        let today = dayStart(context.now, context.calendar)
        let baseline = CutCoachTargets(
            kcal: plan.kcal,
            proteinG: plan.proteinG,
            carbsG: plan.carbsG,
            fatG: plan.fatG,
            training: trainingTarget(from: context.dailyActivities, today: today, calendar: context.calendar)
        )

        var analysis = CutCoachAnalysis()
        var reasons: [CutCoachReason] = []

        let trend = weightTrend(
            readings: context.readings,
            active: active,
            today: today,
            calendar: context.calendar
        )
        let targetLoss = targetLossKgPerWeek(active: active, readings: context.readings, today: today, calendar: context.calendar)
        analysis.observedLossKgPerWeek = trend?.lossKgPerWeek
        analysis.targetLossKgPerWeek = targetLoss

        if let trend, let targetLoss {
            let tolerance = max(0.12, targetLoss * 0.20)
            if trend.lossKgPerWeek + tolerance < targetLoss {
                reasons.append(.init(.trendBelowTarget, "\(trend.windowDays)d trend below target"))
            } else if trend.lossKgPerWeek > targetLoss + tolerance {
                reasons.append(.init(.trendAboveTarget, "\(trend.windowDays)d trend above target"))
            } else {
                reasons.append(.init(.trendOnTarget, "\(trend.windowDays)d trend on target"))
            }
        } else {
            reasons.append(.init(.insufficientWeightData, "insufficient weight data"))
        }

        let food = foodStatus(
            deviations: context.macroDeviations,
            untrackedRanges: context.untrackedRanges,
            today: today,
            calendar: context.calendar
        )
        analysis.sevenDayLoggedMisses = food.loggedMisses
        analysis.sevenDayUntrackedDays = food.untrackedDays
        if food.loggedMisses > 0 {
            reasons.append(.init(.loggedMisses, "\(food.loggedMisses) logged misses in 7d"))
        }
        if food.untrackedDays > 0 {
            reasons.append(.init(.untrackedDays, "\(food.untrackedDays) untracked days in 7d"))
        }
        if !food.hasEnoughData {
            reasons.append(.init(.insufficientFoodData, "insufficient food data"))
        }

        let sleep = sleepStatus(nights: context.sleepNights, today: today, calendar: context.calendar)
        analysis.recentSleepHours = sleep.recentHours
        analysis.baselineSleepHours = sleep.baselineHours
        if sleep.isBelowBaseline {
            reasons.append(.init(.sleepBelowBaseline, "sleep below baseline"))
        } else if !sleep.hasEnoughData {
            reasons.append(.init(.insufficientSleepData, "insufficient sleep data"))
        }

        let activity = activityStatus(activities: context.dailyActivities, today: today, calendar: context.calendar)
        analysis.recentSteps = activity.recentSteps
        analysis.baselineSteps = activity.baselineSteps
        if activity.isBelowBaseline {
            reasons.append(.init(.stepsBelowBaseline, "steps below 7d baseline"))
        } else if !activity.hasEnoughData {
            reasons.append(.init(.insufficientActivityData, "insufficient activity data"))
        }

        let prompt = missingPrompt(
            trend: trend,
            food: food,
            sleep: sleep,
            activity: activity
        )

        let kcalDelta = calorieDelta(
            trend: trend,
            targetLoss: targetLoss,
            food: food,
            sleepBelowBaseline: sleep.isBelowBaseline,
            activityBelowBaseline: activity.isBelowBaseline
        )
        let dailyTargets = targets(from: baseline, kcalDelta: kcalDelta, reasons: &reasons)
        let weeklyTargets = weeklyTargets(from: dailyTargets)

        let decision: CutCoachDecision
        if prompt != nil && trend == nil {
            decision = .requestData
        } else if dailyTargets.kcal < baseline.kcal {
            decision = .lowerCalories
        } else if dailyTargets.kcal > baseline.kcal {
            decision = .raiseCalories
        } else if prompt != nil {
            decision = .requestData
        } else {
            decision = .holdTargets
        }

        return CutCoachRecommendation(
            decision: decision,
            dailyTargets: dailyTargets,
            weeklyTargets: weeklyTargets,
            reasons: unique(reasons),
            prompt: prompt,
            analysis: analysis
        )
    }

    private struct Trend {
        var lossKgPerWeek: Double
        var windowDays: Int
    }

    private struct FoodStatus {
        var loggedMisses: Int
        var untrackedDays: Int
        var averageDailyDeviationKcal: Double
        var hasEnoughData: Bool
    }

    private struct SleepStatus {
        var recentHours: Double?
        var baselineHours: Double?
        var hasEnoughData: Bool
        var isBelowBaseline: Bool
    }

    private struct ActivityStatus {
        var recentSteps: Int?
        var baselineSteps: Int?
        var hasEnoughData: Bool
        var isBelowBaseline: Bool
    }

    private static func calorieDelta(
        trend: Trend?,
        targetLoss: Double?,
        food: FoodStatus,
        sleepBelowBaseline: Bool,
        activityBelowBaseline: Bool
    ) -> Int {
        guard food.hasEnoughData, let trend, let targetLoss else { return 0 }

        let tolerance = max(0.12, targetLoss * 0.20)
        var delta = 0

        if trend.lossKgPerWeek + tolerance < targetLoss {
            delta -= 100
            if food.averageDailyDeviationKcal > 75 {
                delta -= 50
            }
        } else if trend.lossKgPerWeek > targetLoss + tolerance {
            delta += 100
            if food.averageDailyDeviationKcal < -75 {
                delta += 50
            }
        } else if food.averageDailyDeviationKcal > 150 {
            delta -= 50
        } else if food.averageDailyDeviationKcal < -150 {
            delta += 50
        }

        if (sleepBelowBaseline || activityBelowBaseline) && delta < 0 {
            delta = 0
        }

        return max(-150, min(150, delta))
    }

    private static func targets(
        from baseline: CutCoachTargets,
        kcalDelta: Int,
        reasons: inout [CutCoachReason]
    ) -> CutCoachTargets {
        var kcal = roundTo(baseline.kcal + kcalDelta, step: 10)
        if kcal < 1_200 {
            kcal = 1_200
            reasons.append(.init(.calorieGuardrail, "1200 kcal floor"))
        }

        let carbs: Int?
        if let protein = baseline.proteinG, let fat = baseline.fatG {
            let fixedKcal = protein * 4 + fat * 9
            if kcal < fixedKcal {
                kcal = fixedKcal
                carbs = 0
                reasons.append(.init(.calorieGuardrail, "protein fat guardrail"))
            } else {
                carbs = roundDownTo((kcal - fixedKcal) / 4, step: 5)
            }
        } else if let baselineCarbs = baseline.carbsG {
            carbs = max(0, baselineCarbs + roundDownTo(kcalDelta / 4, step: 5))
        } else {
            carbs = nil
        }

        return CutCoachTargets(
            kcal: kcal,
            proteinG: baseline.proteinG,
            carbsG: carbs,
            fatG: baseline.fatG,
            training: baseline.training
        )
    }

    private static func weeklyTargets(from daily: CutCoachTargets) -> CutCoachTargets {
        CutCoachTargets(
            kcal: daily.kcal * 7,
            proteinG: daily.proteinG.map { $0 * 7 },
            carbsG: daily.carbsG.map { $0 * 7 },
            fatG: daily.fatG.map { $0 * 7 },
            training: TrainingTarget(
                steps: daily.training.steps.map { $0 * 7 },
                exerciseMinutes: daily.training.exerciseMinutes.map { $0 * 7 }
            )
        )
    }

    private static func weightTrend(
        readings: [CutCoachReading],
        active: ActiveCut,
        today: Date,
        calendar: Calendar
    ) -> Trend? {
        let daily = dailyReadings(readings, calendar: calendar)
            .filter { $0.date >= dayStart(active.startDate, calendar) && $0.date <= today }
            .sorted { $0.date < $1.date }
        guard daily.count >= 6 else { return nil }

        let recent14 = daily.filter { daysBetween($0.date, today, calendar) <= 13 }
        if recent14.count >= 7,
           let slope = regressionKgPerWeek(recent14, calendar: calendar) {
            return Trend(lossKgPerWeek: -slope, windowDays: 14)
        }

        let recent = daily.filter { daysBetween($0.date, today, calendar) <= 6 }.map(\.weightKg)
        let previous = daily.filter {
            let age = daysBetween($0.date, today, calendar)
            return age >= 7 && age <= 13
        }.map(\.weightKg)

        guard recent.count >= 3, previous.count >= 3 else { return nil }
        let loss = trimmedMean(previous) - trimmedMean(recent)
        return Trend(lossKgPerWeek: loss, windowDays: 14)
    }

    private static func targetLossKgPerWeek(
        active: ActiveCut,
        readings: [CutCoachReading],
        today: Date,
        calendar: Calendar
    ) -> Double? {
        let current = dailyReadings(readings, calendar: calendar)
            .filter { $0.date <= today }
            .max { $0.date < $1.date }?
            .weightKg ?? active.startWeightKg
        let remainingKg = max(0, current - active.targetWeightKg)
        let daysRemaining = max(1, daysBetween(today, dayStart(active.targetEndDate, calendar), calendar))
        return remainingKg / (Double(daysRemaining) / 7.0)
    }

    private static func foodStatus(
        deviations: [CutCoachMacroDeviation],
        untrackedRanges: [CutCoachUntrackedRange],
        today: Date,
        calendar: Calendar
    ) -> FoodStatus {
        var loggedMisses = 0
        var deviationKcal = 0
        var loggedDays = Set<Date>()
        var untrackedDays = Set<Date>()

        for offset in 0..<7 {
            let day = addDays(today, -offset, calendar)
            if untrackedRanges.contains(where: { contains(day, in: $0, calendar: calendar) }) {
                untrackedDays.insert(day)
            }
        }

        for deviation in deviations {
            let day = dayStart(deviation.date, calendar)
            guard daysBetween(day, today, calendar) <= 6, day <= today else { continue }
            loggedDays.insert(day)
            if deviation.direction != .unknown {
                loggedMisses += 1
            }
            deviationKcal += signedKcal(deviation)
        }

        let availableDays = 7 - untrackedDays.count
        // The macro UX is miss-based: days with no logged miss are treated as
        // fine unless the user explicitly marks a range untracked.
        let hasEnoughData = availableDays >= 4
        return FoodStatus(
            loggedMisses: loggedMisses,
            untrackedDays: untrackedDays.count,
            averageDailyDeviationKcal: Double(deviationKcal) / 7.0,
            hasEnoughData: hasEnoughData
        )
    }

    private static func sleepStatus(
        nights: [CutCoachSleepNight],
        today: Date,
        calendar: Calendar
    ) -> SleepStatus {
        let recent = nights.filter {
            let age = daysBetween(dayStart($0.nightDate, calendar), today, calendar)
            return age >= 0 && age <= 6
        }
        let baseline = nights.filter {
            let age = daysBetween(dayStart($0.nightDate, calendar), today, calendar)
            return age >= 7 && age <= 27
        }
        guard recent.count >= 3, baseline.count >= 7 else {
            return SleepStatus(recentHours: meanHours(recent), baselineHours: meanHours(baseline), hasEnoughData: false, isBelowBaseline: false)
        }
        let recentHours = meanHours(recent)
        let baselineHours = meanHours(baseline)
        let below = recentHours.map { recentValue in
            baselineHours.map { recentValue < $0 - 0.5 } ?? false
        } ?? false
        return SleepStatus(recentHours: recentHours, baselineHours: baselineHours, hasEnoughData: true, isBelowBaseline: below)
    }

    private static func activityStatus(
        activities: [CutCoachDailyActivity],
        today: Date,
        calendar: Calendar
    ) -> ActivityStatus {
        let daily = activities.map {
            CutCoachDailyActivity(day: dayStart($0.day, calendar), steps: $0.steps, activeEnergyKcal: $0.activeEnergyKcal, exerciseMinutes: $0.exerciseMinutes)
        }
        let recent = daily.filter {
            let age = daysBetween($0.day, today, calendar)
            return age >= 0 && age <= 2
        }
        let baseline = daily.filter {
            let age = daysBetween($0.day, today, calendar)
            return age >= 3 && age <= 9
        }
        guard recent.count >= 2, baseline.count >= 5 else {
            return ActivityStatus(recentSteps: meanSteps(recent), baselineSteps: meanSteps(baseline), hasEnoughData: false, isBelowBaseline: false)
        }
        let recentSteps = meanSteps(recent)
        let baselineSteps = meanSteps(baseline)
        let below = recentSteps.map { recentValue in
            baselineSteps.map { recentValue < max(0, Int(Double($0) * 0.85)) } ?? false
        } ?? false
        return ActivityStatus(recentSteps: recentSteps, baselineSteps: baselineSteps, hasEnoughData: true, isBelowBaseline: below)
    }

    private static func trainingTarget(
        from activities: [CutCoachDailyActivity],
        today: Date,
        calendar: Calendar
    ) -> TrainingTarget {
        let recent = activities.filter {
            let age = daysBetween(dayStart($0.day, calendar), today, calendar)
            return age >= 0 && age <= 13
        }
        let steps = meanSteps(recent).map { max(5_000, roundTo($0, step: 500)) }
        let exercise = meanExerciseMinutes(recent).map { max(0, roundTo($0, step: 5)) }
        return TrainingTarget(steps: steps, exerciseMinutes: exercise)
    }

    private static func missingPrompt(
        trend: Trend?,
        food: FoodStatus,
        sleep: SleepStatus,
        activity: ActivityStatus
    ) -> CutCoachPrompt? {
        if trend == nil { return .bodyWeight }
        if !food.hasEnoughData { return .macroDeviation }
        if !sleep.hasEnoughData { return .sleep }
        if !activity.hasEnoughData { return .steps }
        return nil
    }

    private static func dailyReadings(_ readings: [CutCoachReading], calendar: Calendar) -> [CutCoachReading] {
        var byDay: [Date: CutCoachReading] = [:]
        for reading in readings {
            let day = dayStart(reading.date, calendar)
            byDay[day] = CutCoachReading(
                date: day,
                weightKg: reading.weightKg,
                waistCm: reading.waistCm,
                hipsCm: reading.hipsCm,
                note: reading.note
            )
        }
        return Array(byDay.values)
    }

    private static func regressionKgPerWeek(_ readings: [CutCoachReading], calendar: Calendar) -> Double? {
        guard readings.count >= 2, let first = readings.first?.date else { return nil }
        let xs = readings.map { Double(daysBetween(first, $0.date, calendar)) }
        let ys = readings.map(\.weightKg)
        let xMean = xs.reduce(0, +) / Double(xs.count)
        let yMean = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var denominator = 0.0
        for idx in xs.indices {
            let dx = xs[idx] - xMean
            numerator += dx * (ys[idx] - yMean)
            denominator += dx * dx
        }
        guard denominator > 0 else { return nil }
        return (numerator / denominator) * 7.0
    }

    private static func trimmedMean(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard sorted.count >= 3 else {
            return sorted.reduce(0, +) / Double(max(1, sorted.count))
        }
        let trimmed = Array(sorted.dropFirst().dropLast())
        return trimmed.reduce(0, +) / Double(trimmed.count)
    }

    private static func signedKcal(_ deviation: CutCoachMacroDeviation) -> Int {
        let value: Int
        switch deviation.magnitude {
        case .slight: value = 150
        case .moderate: value = 300
        case .large: value = 600
        case .wayOff: value = 450
        }
        switch deviation.direction {
        case .over: return value
        case .under: return -value
        case .unknown: return 0
        }
    }

    private static func meanHours(_ nights: [CutCoachSleepNight]) -> Double? {
        guard !nights.isEmpty else { return nil }
        let minutes = nights.reduce(0) { $0 + max(0, $1.asleepMinutes) }
        return Double(minutes) / 60.0 / Double(nights.count)
    }

    private static func meanSteps(_ activities: [CutCoachDailyActivity]) -> Int? {
        guard !activities.isEmpty else { return nil }
        return activities.reduce(0) { $0 + max(0, $1.steps) } / activities.count
    }

    private static func meanExerciseMinutes(_ activities: [CutCoachDailyActivity]) -> Int? {
        let values = activities.compactMap(\.exerciseMinutes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private static func unique(_ reasons: [CutCoachReason]) -> [CutCoachReason] {
        var seen = Set<String>()
        var result: [CutCoachReason] = []
        for reason in reasons where !seen.contains(reason.text) {
            seen.insert(reason.text)
            result.append(reason)
        }
        return result
    }

    private static func contains(_ day: Date, in range: CutCoachUntrackedRange, calendar: Calendar) -> Bool {
        day >= dayStart(range.startDate, calendar) && day <= dayStart(range.endDate, calendar)
    }

    private static func dayStart(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func addDays(_ date: Date, _ days: Int, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    private static func daysBetween(_ start: Date, _ end: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: dayStart(start, calendar), to: dayStart(end, calendar)).day ?? 0
    }

    private static func roundTo(_ value: Int, step: Int) -> Int {
        guard step > 0 else { return value }
        return Int((Double(value) / Double(step)).rounded()) * step
    }

    private static func roundDownTo(_ value: Int, step: Int) -> Int {
        guard step > 0 else { return value }
        return Int((Double(value) / Double(step)).rounded(.down)) * step
    }
}
