import Foundation
import SwiftUI

@MainActor
final class CutsViewModel: ObservableObject {
    @Published var activeCut: ActiveCut?
    @Published var historicalCuts: [HistoricalCut] = []
    @Published var mostRecentReading: Reading?
    @Published var allReadings: [Reading] = []
    @Published var projection: CutProjectionResult?
    @Published var cutCoachPlan: CutCoachPlan?

    private let services: AppServices

    init(services: AppServices = .shared) {
        self.services = services
    }

    func reload() {
        activeCut = ActiveCutStore.load()
        let readings = services.repository.allReadings()
        allReadings = readings
        mostRecentReading = readings.last
        let clusters = ClusterDetector.clusters(from: readings)
        let detected = HistoricalCutDetector.detect(in: clusters, readings: readings)
        historicalCuts = detected.sorted { $0.startDate > $1.startDate }
        projection = CutProjection.project(active: activeCut, readings: readings, historicalCuts: detected)
        applyCutCoachRecommendation(services.cutCoach.refresh(trigger: .manual))
    }

    func startCut(_ cut: ActiveCut) async {
        ActiveCutStore.save(cut)
        activeCut = cut
        applyCutCoachRecommendation(services.cutCoach.refresh(trigger: .activeCutChanged))
        await services.notifications.scheduleEvaluatedTriggers()
        reload()
    }

    func updateCut(_ cut: ActiveCut) async {
        ActiveCutStore.save(cut)
        activeCut = cut
        applyCutCoachRecommendation(services.cutCoach.refresh(trigger: .activeCutChanged))
        await services.notifications.scheduleEvaluatedTriggers()
        reload()
    }

    func markDone() async {
        ActiveCutStore.save(nil)
        activeCut = nil
        services.cutCoach.clear(trigger: .activeCutChanged)
        applyCutCoachRecommendation(nil)
        await services.notifications.scheduleEvaluatedTriggers()
        reload()
    }

    // MARK: - Active cut metrics

    /// Current weight from the most recent reading (kg).
    var currentWeightKg: Double? { mostRecentReading?.weightKg }

    /// Actual rate of loss in lb/week from start to today.
    func actualRateLbPerWeek(now: Date = Date()) -> Double? {
        guard let cut = activeCut, let current = currentWeightKg else { return nil }
        let elapsed = max(1, cut.daysElapsed(now: now))
        let lossKg = cut.startWeightKg - current
        let weeks = Double(elapsed) / 7.0
        guard weeks > 0 else { return nil }
        return UnitConvert.kgToLb(lossKg) / weeks
    }

    /// Needed rate of loss in lb/week from today to target end date.
    func neededRateLbPerWeek(now: Date = Date()) -> Double? {
        guard let cut = activeCut, let current = currentWeightKg else { return nil }
        let remaining = max(1, cut.daysRemaining(now: now))
        let remainingLossKg = current - cut.targetWeightKg
        let weeks = Double(remaining) / 7.0
        guard weeks > 0 else { return nil }
        return UnitConvert.kgToLb(remainingLossKg) / weeks
    }

    enum CutStatus { case onTrack, behind, reversed }

    /// Compare actual vs needed rate. Reversed = gaining; behind = positive but below needed.
    func status(now: Date = Date()) -> CutStatus? {
        guard let actual = actualRateLbPerWeek(now: now),
              let needed = neededRateLbPerWeek(now: now) else { return nil }
        if actual <= 0 { return .reversed }
        if actual + 0.05 < needed { return .behind }
        return .onTrack
    }

    /// Projected end weight if we continue at the actual rate (kg).
    func projectedEndWeightKg(now: Date = Date()) -> Double? {
        guard let cut = activeCut, let current = currentWeightKg,
              let actualLb = actualRateLbPerWeek(now: now) else { return nil }
        let remaining = max(0, cut.daysRemaining(now: now))
        let weeks = Double(remaining) / 7.0
        let projectedLossKg = UnitConvert.lbToKg(actualLb * weeks)
        return current - projectedLossKg
    }

    /// Age (in years rounded down) at the start of a historical cut. Requires birthdate;
    /// since none is stored, we return the elapsed years from the cut start to today as a
    /// proxy "age at the time" placeholder. Spec wording: "age at the time" — display the
    /// duration since that cut.
    func yearsAgo(of date: Date, now: Date = Date()) -> Int {
        let comps = Calendar.current.dateComponents([.year], from: date, to: now)
        return max(0, comps.year ?? 0)
    }

    // MARK: - Cut coach

    func applyCutCoachRecommendation(_ recommendation: CutCoachRecommendation?) {
        cutCoachPlan = makeCutCoachPlan(recommendation)
    }

    private func makeCutCoachPlan(_ recommendation: CutCoachRecommendation?) -> CutCoachPlan? {
        guard let recommendation, let targets = recommendation.dailyTargets else { return nil }
        return CutCoachPlan(
            calories: targets.kcal,
            proteinG: targets.proteinG,
            fatG: targets.fatG,
            carbsG: targets.carbsG,
            steps: targets.training.steps,
            trainingTarget: trainingText(targets.training),
            weekStatus: statusText(recommendation.decision),
            weekDecision: decisionText(recommendation),
            reasons: CutCoachCopy.reasonBullets(recommendation.reasons.map(\.text)),
            missingDetailPrompt: prompt(for: recommendation.prompt)
        )
    }

    private func statusText(_ decision: CutCoachDecision) -> String {
        switch decision {
        case .holdTargets: return "Hold"
        case .lowerCalories: return "Adjust"
        case .raiseCalories: return "Adjust"
        case .requestData: return "Gather data"
        case .noActiveCut: return "No active cut"
        }
    }

    private func decisionText(_ recommendation: CutCoachRecommendation) -> String? {
        switch recommendation.decision {
        case .holdTargets:
            return "No change"
        case .lowerCalories:
            guard let kcal = recommendation.dailyTargets?.kcal else { return "Lower calories" }
            return "\(kcal) kcal/day"
        case .raiseCalories:
            guard let kcal = recommendation.dailyTargets?.kcal else { return "Raise calories" }
            return "\(kcal) kcal/day"
        case .requestData:
            return recommendation.prompt?.title
        case .noActiveCut:
            return nil
        }
    }

    private func trainingText(_ target: TrainingTarget) -> String? {
        guard let minutes = target.exerciseMinutes, minutes > 0 else { return nil }
        return "\(minutes) min"
    }

    private func prompt(for prompt: CutCoachPrompt?) -> CutCoachMissingDetailPrompt? {
        guard let prompt else { return nil }
        switch prompt {
        case .macroDeviation:
            return CutCoachMissingDetailPrompt(question: "What explains the missing food signal?")
        case .bodyWeight:
            return CutCoachMissingDetailPrompt(question: "What explains the missing weight signal?")
        case .sleep:
            return CutCoachMissingDetailPrompt(question: "What explains the missing sleep signal?")
        case .steps:
            return CutCoachMissingDetailPrompt(question: "What explains the missing activity signal?")
        case .macroPlan:
            return nil
        }
    }
}
