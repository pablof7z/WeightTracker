import Foundation

/// Forward-projects body weight `horizon` days into the future using the same
/// EWMA trend + 14-day OLS slope + phase multipliers that `CutDeficitEstimator`
/// uses. The projection is an exponential-approach curve (the "plateau
/// principle" / linearization of Hall's body-weight ODE): linear for short
/// horizons, gently concave for long ones.
///
/// Math (see `/tmp/projected-weight-math-brainstorm.md`):
///
///   W_today  = trend[asOf]   (EWMA trend, α = 0.10)
///   r_obs    = OLS slope of trailing 14 days of trend (kg/day; +ve when gaining)
///   r_ss     = -r_obs · (current_phase_kcal_per_lb / steady_state_kcal_per_lb)
///              — i.e. "kg lost per day, positive when losing". The phase
///              correction makes the slope honest: a 0.2 lb/day cut in the
///              transition phase (k=2500) projects forward as the steady-state
///              equivalent 0.167 lb/day, because steady-state energy density
///              is higher and tomorrow's pound takes more deficit.
///   τ        = 320 days (Hall plateau time constant; t½ ≈ 222d)
///   ΔW       = r_ss · τ · (1 − exp(−Δt / τ))    (kg, positive when losing)
///   W_proj   = W_today − ΔW
///
/// Uncertainty (95% band): `1.96 · SE_slope · Δt`, where SE_slope is the
/// standard error of the OLS slope coefficient from the 14-day regression
/// (kg/day). This is intentionally a simple slope-propagation band — no σ_water
/// floor, no thermogenesis drift — per the spec.
///
/// Returns nil when:
///   - cut is missing, hasn't started, or has already ended,
///   - we have fewer than 14 days of cut data,
///   - the 95% half-band exceeds 5 lb (too wide to be useful).
public enum CutWeightProjector {

    // MARK: - Constants

    /// Exponential-approach time constant in days. ≈ 320d (t½ ≈ 222d) — see
    /// the math brainstorm §1. For Δt ≤ ~120d the linear vs. exponential
    /// spread is small (< ~3 lb) but enough to justify modeling.
    public static let tauDays: Double = 320

    /// 95% confidence multiplier (normal approximation).
    private static let z95: Double = 1.96

    /// Minimum days of cut data required before we show a projection. Matches
    /// the UX brainstorm's "<14 days → hide" rule.
    public static let minCutDays: Int = 14

    /// Half-width band ceiling (lb). If the 95% half-width exceeds this, the
    /// projection is too noisy to surface and we return nil. 5 lb is
    /// approximately ±2.27 kg.
    private static let maxBandLb: Double = 5.0

    /// Flat-slope threshold (lb/day). If |r_ss| < this, the result reports
    /// `isFlat == true` instead of a numeric projection so the widget can
    /// render "no change projected" instead of an essentially-noise number.
    private static let flatSlopeLbPerDay: Double = 0.01

    // MARK: - Result

    public struct Result: Sendable {
        public let projectedKg: Double
        public let lowerKg: Double
        public let upperKg: Double
        public let asOfDate: Date
        public let horizonDate: Date
        /// Steady-state-equivalent rate, in kg/week. Positive = losing.
        /// Used by the widget for adaptive copy.
        public let slopeKgPerWeek: Double
        /// True when |slope| is below the flat threshold; the widget should
        /// render "no change projected" instead of a number.
        public let isFlat: Bool
        /// Projection at the active cut's target end date, when one exists
        /// and isn't the same as `horizonDate`. The widget needs this so the
        /// caption can carry a "goal Aug 21" anchor regardless of which
        /// horizon is currently displayed.
        public let projectionAtGoalKg: Double?
    }

    // MARK: - Entry point

    public static func project(
        activeCut: ActiveCut?,
        readings: [Reading],
        horizonDays: Int,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> Result? {
        guard let cut = activeCut else { return nil }

        let cutStartDay = calendar.startOfDay(for: cut.startDate)
        let today = calendar.startOfDay(for: asOf)
        let daysSinceStart = calendar.dateComponents([.day], from: cutStartDay, to: today).day ?? 0

        // Cut hasn't started, or fewer than 14 days in.
        guard daysSinceStart >= minCutDays else { return nil }

        // Cut already ended — no forward projection makes sense here.
        let cutEndDay = calendar.startOfDay(for: cut.targetEndDate)
        guard cutEndDay > today else { return nil }

        // Build the same EWMA trend the deficit estimator uses. Reusing the
        // exact helper keeps the projector and the deficit widget perfectly
        // consistent — same α, same seeding, same daily interpolation.
        let trend = CutDeficitEstimator.buildEwmaTrend(
            readings: readings,
            cutStart: cutStartDay,
            asOf: today,
            calendar: calendar
        )
        guard let wTodayKg = trend[today] else { return nil }

        // Build the trailing-14-day series in kg, indexed by day.
        let windowDays = min(CutDeficitEstimator.dailyRateWindowDays, daysSinceStart + 1)
        var series: [(x: Double, y: Double)] = []
        series.reserveCapacity(windowDays)
        for offset in (0..<windowDays).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let kg = trend[calendar.startOfDay(for: day)] else { continue }
            series.append((Double(windowDays - 1 - offset), kg))
        }
        guard series.count >= 2 else { return nil }

        let fit = olsSlopeWithSE(series)
        let slopeKgPerDay = fit.slope // +ve when gaining
        let slopeSEKgPerDay = fit.standardError

        // Phase-adjust the slope to the steady-state equivalent. We flip the
        // sign at the same time: `rSS` is "kg lost per day, +ve when losing"
        // so the rest of the math reads naturally (ΔW = rSS · τ · (1-e^(-h/τ))
        // is the loss; subtract from W_today to project forward).
        let currentPhase = CutDeficitEstimator.CutPhase.phase(forDay: daysSinceStart)
        let phaseRatio = currentPhase.kcalPerLb / CutDeficitEstimator.CutPhase.steadyState.kcalPerLb
        let rSSKgPerDay = -slopeKgPerDay * phaseRatio

        let isFlat = abs(UnitConvert.kgToLb(rSSKgPerDay)) < flatSlopeLbPerDay

        // Reject projections whose 95% half-band exceeds the configured
        // ceiling. The band scales linearly with horizon, so wider horizons
        // are more likely to be rejected — which is the intent: don't show
        // numbers with noise dwarfing signal.
        let halfBandKg = z95 * slopeSEKgPerDay * Double(horizonDays)
        if halfBandKg > UnitConvert.lbToKg(maxBandLb) { return nil }

        // Exponential-approach projection.
        let h = Double(horizonDays)
        let approach = 1.0 - exp(-h / tauDays)
        let deltaKg = rSSKgPerDay * tauDays * approach
        let projectedKg = wTodayKg - deltaKg

        let horizonDate = calendar.date(byAdding: .day, value: horizonDays, to: today) ?? today

        // Optional: projection at the cut's target end date, if that date is
        // not the same horizon being rendered. The widget uses this for the
        // small "goal Aug 21" anchor on every horizon.
        let projectionAtGoalKg: Double? = {
            guard cutEndDay != calendar.startOfDay(for: horizonDate) else { return nil }
            let goalDays = max(1, calendar.dateComponents([.day], from: today, to: cutEndDay).day ?? 1)
            let approachGoal = 1.0 - exp(-Double(goalDays) / tauDays)
            return wTodayKg - rSSKgPerDay * tauDays * approachGoal
        }()

        return Result(
            projectedKg: projectedKg,
            lowerKg: projectedKg - halfBandKg,
            upperKg: projectedKg + halfBandKg,
            asOfDate: today,
            horizonDate: horizonDate,
            slopeKgPerWeek: rSSKgPerDay * 7.0,
            isFlat: isFlat,
            projectionAtGoalKg: projectionAtGoalKg
        )
    }

    // MARK: - OLS with standard error

    /// OLS slope + standard error of the slope coefficient.
    /// SE_slope = sqrt( (Σ residual²/(n-2)) / Σ(x-x̄)² ).
    /// Returns (0, .infinity) for degenerate input so the caller's band gate
    /// rejects the projection.
    private static func olsSlopeWithSE(_ points: [(x: Double, y: Double)]) -> (slope: Double, standardError: Double) {
        let n = Double(points.count)
        guard n >= 2 else { return (0, .infinity) }
        let meanX = points.map(\.x).reduce(0, +) / n
        let meanY = points.map(\.y).reduce(0, +) / n
        var sxx = 0.0
        var sxy = 0.0
        for p in points {
            let dx = p.x - meanX
            sxx += dx * dx
            sxy += dx * (p.y - meanY)
        }
        guard sxx > 0 else { return (0, .infinity) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        guard n > 2 else {
            // With only 2 points, residuals are zero and SE is undefined.
            // Treat as "no usable uncertainty" → infinity → rejected by band gate.
            return (slope, .infinity)
        }
        var rss = 0.0
        for p in points {
            let yHat = intercept + slope * p.x
            let r = p.y - yHat
            rss += r * r
        }
        let residualVariance = rss / (n - 2.0)
        let seSlope = sqrt(residualVariance / sxx)
        return (slope, seSlope)
    }
}
