import Foundation
import CryptoKit
import SwiftUI

@MainActor
final class CutCoachService: ObservableObject {
    @Published private(set) var recommendation: CutCoachRecommendation?
    @Published private(set) var lastEvaluatedAt: Date?

    private let repository: ReadingRepository
    private let macroPlanStore: MacroPlanStore
    private let macroDeviationStore: MacroDeviationStore
    private let macroUntrackedRangeStore: MacroUntrackedRangeStore
    private let auditStore: CoachAuditStore

    init(
        repository: ReadingRepository,
        macroPlanStore: MacroPlanStore,
        macroDeviationStore: MacroDeviationStore,
        macroUntrackedRangeStore: MacroUntrackedRangeStore,
        auditStore: CoachAuditStore
    ) {
        self.repository = repository
        self.macroPlanStore = macroPlanStore
        self.macroDeviationStore = macroDeviationStore
        self.macroUntrackedRangeStore = macroUntrackedRangeStore
        self.auditStore = auditStore
    }

    @discardableResult
    func refresh(now: Date = Date(), trigger: CoachRunTrigger = .manual) -> CutCoachRecommendation? {
        guard let activeCut = ActiveCutStore.load() else {
            let context = makeContext(activeCut: nil, now: now)
            let next = CutCoachEngine.evaluate(context: context)
            persistRun(context: context, recommendation: next, trigger: trigger, now: now)
            recommendation = nil
            lastEvaluatedAt = now
            return nil
        }

        let context = makeContext(activeCut: activeCut, now: now)
        let next = CutCoachEngine.evaluate(context: context)
        persistRun(context: context, recommendation: next, trigger: trigger, now: now)
        recommendation = next
        lastEvaluatedAt = now
        return next
    }

    func clear(now: Date = Date(), trigger: CoachRunTrigger = .activeCutChanged) {
        let context = makeContext(activeCut: nil, now: now)
        let next = CutCoachEngine.evaluate(context: context)
        persistRun(context: context, recommendation: next, trigger: trigger, now: now)
        recommendation = nil
        lastEvaluatedAt = now
    }

    @discardableResult
    func appendVoiceCheckInNote(
        transcript: String,
        audioDraftID: UUID?,
        now: Date = Date()
    ) -> CoachNote? {
        auditStore.appendNote(
            source: .user,
            kind: .checkIn,
            visibility: .userVisible,
            cutStartDate: ActiveCutStore.load()?.startDate,
            day: now,
            text: transcript,
            audioDraftID: audioDraftID,
            createdAt: now
        )
    }

    func recentAuditRuns(limit: Int = 50) -> [CoachRun] {
        auditStore.recentRuns(limit: limit)
    }

    func recentNotes(limit: Int = 50, userVisibleOnly: Bool = false) -> [CoachNote] {
        auditStore.recentNotes(limit: limit, userVisibleOnly: userVisibleOnly)
    }

    private func makeContext(activeCut: ActiveCut?, now: Date) -> CutCoachContext {
        let cutStart = activeCut.map { Reading.dayStart(of: $0.startDate) }
        return CutCoachContext(
            activeCut: activeCut,
            planPeriod: cutStart
                .flatMap { macroPlanStore.currentPeriod(forCutStartDate: $0) }
                .map(CutCoachMacroPlan.init),
            readings: repository.allReadings().map(CutCoachReading.init),
            macroDeviations: cutStart
                .map { macroDeviationStore.deviations(forCutStartDate: $0).map(CutCoachMacroDeviation.init) }
                ?? [],
            untrackedRanges: cutStart
                .map { macroUntrackedRangeStore.ranges(forCutStartDate: $0).map(CutCoachUntrackedRange.init) }
                ?? [],
            sleepNights: repository.allSleepNights().map(CutCoachSleepNight.init),
            dailyActivities: repository.allDailyActivities().map(CutCoachDailyActivity.init),
            now: now,
            calendar: .current
        )
    }

    private func persistRun(
        context: CutCoachContext,
        recommendation: CutCoachRecommendation,
        trigger: CoachRunTrigger,
        now: Date
    ) {
        let contextData = encode(CoachContextAuditSnapshot(context))
        let recommendationData = encode(CoachRecommendationAuditSnapshot(recommendation))
        let run = auditStore.beginRun(
            kind: .deterministicRefresh,
            trigger: trigger,
            cutStartDate: context.activeCut?.startDate,
            contextFingerprint: contextData.map(Self.fingerprint) ?? UUID().uuidString,
            contextSnapshotJSON: contextData,
            now: now
        )
        auditStore.completeRun(run, recommendationJSON: recommendationData, now: now)
    }

    private func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    private static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct CoachContextAuditSnapshot: Encodable {
    var now: Date
    var activeCut: ActiveCut?
    var plan: Plan?
    var readings: [ReadingSnapshot]
    var macroDeviations: [MacroDeviationSnapshot]
    var untrackedRanges: [UntrackedRangeSnapshot]
    var sleepNights: [SleepSnapshot]
    var dailyActivities: [ActivitySnapshot]

    init(_ context: CutCoachContext) {
        now = context.now
        activeCut = context.activeCut
        plan = context.planPeriod.map(Plan.init)
        readings = context.readings.suffix(35).map(ReadingSnapshot.init)
        macroDeviations = context.macroDeviations.suffix(35).map(MacroDeviationSnapshot.init)
        untrackedRanges = context.untrackedRanges.suffix(20).map(UntrackedRangeSnapshot.init)
        sleepNights = context.sleepNights.suffix(35).map(SleepSnapshot.init)
        dailyActivities = context.dailyActivities.suffix(35).map(ActivitySnapshot.init)
    }

    struct Plan: Encodable {
        var startDate: Date
        var endDate: Date?
        var kcal: Int
        var proteinG: Int?
        var carbsG: Int?
        var fatG: Int?
        var tag: String

        init(_ plan: CutCoachMacroPlan) {
            startDate = plan.startDate
            endDate = plan.endDate
            kcal = plan.kcal
            proteinG = plan.proteinG
            carbsG = plan.carbsG
            fatG = plan.fatG
            tag = plan.tag.rawValue
        }
    }

    struct ReadingSnapshot: Encodable {
        var date: Date
        var weightKg: Double
        var waistCm: Double?
        var hipsCm: Double?
        var hasNote: Bool

        init(_ reading: CutCoachReading) {
            date = reading.date
            weightKg = reading.weightKg
            waistCm = reading.waistCm
            hipsCm = reading.hipsCm
            hasNote = reading.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    struct MacroDeviationSnapshot: Encodable {
        var date: Date
        var direction: String
        var magnitude: String

        init(_ deviation: CutCoachMacroDeviation) {
            date = deviation.date
            direction = deviation.direction.rawValue
            magnitude = deviation.magnitude.rawValue
        }
    }

    struct UntrackedRangeSnapshot: Encodable {
        var startDate: Date
        var endDate: Date
        var reason: String

        init(_ range: CutCoachUntrackedRange) {
            startDate = range.startDate
            endDate = range.endDate
            reason = range.reason.rawValue
        }
    }

    struct SleepSnapshot: Encodable {
        var nightDate: Date
        var asleepMinutes: Int

        init(_ night: CutCoachSleepNight) {
            nightDate = night.nightDate
            asleepMinutes = night.asleepMinutes
        }
    }

    struct ActivitySnapshot: Encodable {
        var day: Date
        var steps: Int
        var activeEnergyKcal: Double?
        var exerciseMinutes: Int?

        init(_ activity: CutCoachDailyActivity) {
            day = activity.day
            steps = activity.steps
            activeEnergyKcal = activity.activeEnergyKcal
            exerciseMinutes = activity.exerciseMinutes
        }
    }
}

private struct CoachRecommendationAuditSnapshot: Encodable {
    var decision: String
    var dailyTargets: Targets?
    var weeklyTargets: Targets?
    var reasons: [Reason]
    var prompt: String?
    var analysis: Analysis

    init(_ recommendation: CutCoachRecommendation) {
        decision = recommendation.decision.rawValue
        dailyTargets = recommendation.dailyTargets.map(Targets.init)
        weeklyTargets = recommendation.weeklyTargets.map(Targets.init)
        reasons = recommendation.reasons.map(Reason.init)
        prompt = recommendation.prompt?.rawValue
        analysis = Analysis(recommendation.analysis)
    }

    struct Targets: Encodable {
        var kcal: Int
        var proteinG: Int?
        var carbsG: Int?
        var fatG: Int?
        var steps: Int?
        var exerciseMinutes: Int?

        init(_ targets: CutCoachTargets) {
            kcal = targets.kcal
            proteinG = targets.proteinG
            carbsG = targets.carbsG
            fatG = targets.fatG
            steps = targets.training.steps
            exerciseMinutes = targets.training.exerciseMinutes
        }
    }

    struct Reason: Encodable {
        var code: String
        var text: String

        init(_ reason: CutCoachReason) {
            code = reason.code.rawValue
            text = reason.text
        }
    }

    struct Analysis: Encodable {
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
}
