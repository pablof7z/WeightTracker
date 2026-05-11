import Foundation
import SwiftUI
import SwiftData

@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let modelContainer: ModelContainer
    let repository: ReadingRepository
    let healthKit: HealthKitManager
    let notifications: NotificationService
    let sleepHealthKit: SleepHealthKit
    let activityHealthKit: ActivityHealthKit
    let cycleHealthKit: CycleHealthKit

    // Macro feature stores (M1)
    let macroPlanStore: MacroPlanStore
    let macroUntrackedRangeStore: MacroUntrackedRangeStore
    let macroDeviationStore: MacroDeviationStore
    let mealScheduleStore: MealScheduleStore
    let mealEventStore: MealEventStore
    let coachAuditStore: CoachAuditStore
    let coachProposalStore: CoachProposalStore
    let scheduledNudgeStore: ScheduledNudgeStore
    let mealCalculator: MealCalculator
    let coachAgent: CoachAgentSession
    let coachNostrAgent: CoachNostrAgentService
    let feedback: FeedbackService

    @Published var lastSyncDate: Date?

    private init() {
        let container = ModelContainerFactory.makeContainer()
        self.modelContainer = container
        self.repository = SwiftDataReadingRepository(container: container)
        self.healthKit = HealthKitManager(repository: repository)
        self.notifications = NotificationService(repository: repository)
        self.sleepHealthKit = SleepHealthKit(repository: repository)
        self.activityHealthKit = ActivityHealthKit(repository: repository)
        self.cycleHealthKit = CycleHealthKit()

        let planStore = MacroPlanStore(container: container)
        let untrackedStore = MacroUntrackedRangeStore(container: container)
        let deviationStore = MacroDeviationStore(
            container: container,
            untrackedStore: untrackedStore,
            planStore: planStore
        )
        self.macroPlanStore = planStore
        self.macroUntrackedRangeStore = untrackedStore
        self.macroDeviationStore = deviationStore
        let mealSchedule = MealScheduleStore(container: container)
        let mealEvents = MealEventStore(container: container)
        self.mealScheduleStore = mealSchedule
        self.mealEventStore = mealEvents
        let auditStore = CoachAuditStore(container: container)
        self.coachAuditStore = auditStore
        self.coachProposalStore = CoachProposalStore(container: container)
        let nudgeStore = ScheduledNudgeStore(container: container)
        self.scheduledNudgeStore = nudgeStore

        let nostrAgent = CoachNostrAgentService()
        self.coachNostrAgent = nostrAgent
        self.feedback = FeedbackService()

        let coachModel = UserDefaults.standard.string(forKey: AppPrefKey.openRouterModel)
            ?? AppConstants.defaultOpenRouterModel
        // The calculator shares the OpenRouter credential pool with the
        // outer agent — the inner gpt-4o-mini call goes through the same
        // account that powers the coach.
        let calculator = MealCalculator(openRouterClient: CoachOpenRouterClient())
        self.mealCalculator = calculator
        let agent = CoachAgentSession(
            repository: repository,
            macroPlanStore: planStore,
            macroDeviationStore: deviationStore,
            macroUntrackedRangeStore: untrackedStore,
            mealScheduleStore: mealSchedule,
            mealEventStore: mealEvents,
            auditStore: auditStore,
            mealCalculator: calculator,
            scheduledNudgeStore: nudgeStore,
            model: coachModel,
            recordMemory: { text in
                try nostrAgent.recordMemory(text: text)
            },
            pinTodayNote: { text in
                TodayPinnedNoteStore.shared.pin(text: text)
            }
        )
        self.coachAgent = agent

        nostrAgent.onKind1Mention = { [agent, nostrAgent] event in
            let thread = await nostrAgent.fetchThread(for: event)
            await agent.run(transcript: event.content, trigger: .nostrConversation)
            guard let text = agent.lastFinalAssistantText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return }
            do {
                _ = try await nostrAgent.reply(to: event, content: text, threadEvents: thread)
            } catch {
                // Nostr replies are best-effort; the audit already records the coach run.
            }
        }
    }

    func bootstrap() async {
        // Don't auto-request notification permission — let onboarding/Settings ask explicitly.
        await healthKit.startObservingIfAuthorized()
        await sleepHealthKit.startObservingIfAuthorized()
        await activityHealthKit.startObservingIfAuthorized()
        await cycleHealthKit.fetchAndStoreCycleStartsIfEnabled()
        await notifications.scheduleEvaluatedTriggers()
        await feedback.start(appName: "WeightTracker")
        coachNostrAgent.start()
        await scheduledNudgeStore.syncToNotificationCenter()
        scheduleEveningReviewIfNeeded()
    }

    /// Schedule tonight's 9pm coach review nudge if an active cut is running
    /// and we haven't already done so today.
    private func scheduleEveningReviewIfNeeded() {
        guard ActiveCutStore.load() != nil else { return }
        let cal = Calendar.current
        let key = "coach.eveningReviewScheduledDay"
        let today = cal.startOfDay(for: Date())
        let lastScheduled = UserDefaults.standard.object(forKey: key) as? Date
        guard lastScheduled.map({ cal.startOfDay(for: $0) != today }) ?? true else { return }

        // Build a 9pm fire time for tonight.
        guard let ninepm = cal.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) else { return }
        guard ninepm > Date() else { return }

        scheduledNudgeStore.schedule(
            message: "How did today go? Coach is ready to review.",
            triggerType: .timeOfDay,
            triggerParams: "{\"hour\":21,\"minute\":0}",
            expiresAt: cal.date(byAdding: .hour, value: 3, to: ninepm)
        )
        Task { await scheduledNudgeStore.syncToNotificationCenter() }
        UserDefaults.standard.set(Date(), forKey: key)
    }

    var cycleStarts: [Date] {
        guard UserDefaults.standard.bool(forKey: AppPrefKey.cycleAdjustmentEnabled) else { return [] }
        return cycleHealthKit.loadStoredCycleStarts()
    }
}
