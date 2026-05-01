import Foundation

/// Computes a starting macro plan for a cut from the user's body priors and the
/// cut's loss target. Mifflin–St Jeor BMR × activity factor → TDEE; subtract a
/// daily kcal deficit derived from `(totalLossKg × 7700) / days`, floored at
/// 1200 kcal. Protein anchored to start weight in lb, fat at 0.3 g/lb (min 40g),
/// carbs absorb the remainder.
public struct MacroDefaults {
    public static func totalKcal(proteinG: Int, fatG: Int, carbsG: Int) -> Int {
        proteinG * 4 + fatG * 9 + carbsG * 4
    }

    /// Mifflin–St Jeor basal metabolic rate (kcal/day).
    public static func bmr(weightKg: Double, heightCm: Double, ageYears: Int, sex: Sex) -> Double {
        let base = 10.0 * weightKg + 6.25 * heightCm - 5.0 * Double(ageYears)
        switch sex {
        case .male:        return base + 5
        case .female:      return base - 161
        case .unspecified: return base - 78
        }
    }

    private static func roundTo(_ x: Double, step: Int) -> Int {
        let s = Double(step)
        return Int((x / s).rounded()) * step
    }

    public static func compute(
        startWeightKg: Double,
        targetWeightKg: Double,
        startDate: Date,
        targetEndDate: Date,
        sex: Sex,
        ageYears: Int,
        heightCm: Double,
        activityFactor: Double
    ) -> (kcal: Int, proteinG: Int, fatG: Int, carbsG: Int) {
        let lb = startWeightKg * 2.20462
        let proteinG = roundTo(1.0 * lb, step: 5)
        let fatG = max(40, Int((0.3 * lb / 5.0).rounded(.down)) * 5)

        let bmrVal = bmr(weightKg: startWeightKg, heightCm: heightCm, ageYears: ageYears, sex: sex)
        let tdee = bmrVal * activityFactor

        let totalLossKg = max(0, startWeightKg - targetWeightKg)
        let days = max(7, targetEndDate.timeIntervalSince(startDate) / 86400)
        let dailyDeficit = (totalLossKg * 7700.0) / days
        let kcalRaw = max(1200.0, tdee - dailyDeficit)
        let kcal = roundTo(kcalRaw, step: 10)

        let proteinKcal = proteinG * 4
        let fatKcal = fatG * 9
        let carbKcal = max(0, kcal - proteinKcal - fatKcal)
        let carbsG = max(0, Int((Double(carbKcal) / 4.0 / 5.0).rounded(.down)) * 5)

        return (kcal, proteinG, fatG, carbsG)
    }
}
