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

    // Macro feature stores (M1)
    let macroPlanStore: MacroPlanStore
    let macroUntrackedRangeStore: MacroUntrackedRangeStore
    let macroDeviationStore: MacroDeviationStore
    let coachAuditStore: CoachAuditStore
    let coachAgent: CoachAgentSession
    let coachNostrAgent: CoachNostrAgentService

    @Published var lastSyncDate: Date?

    private init() {
        let container = ModelContainerFactory.makeContainer()
        self.modelContainer = container
        self.repository = SwiftDataReadingRepository(container: container)
        self.healthKit = HealthKitManager(repository: repository)
        self.notifications = NotificationService(repository: repository)
        self.sleepHealthKit = SleepHealthKit(repository: repository)
        self.activityHealthKit = ActivityHealthKit(repository: repository)

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
        let auditStore = CoachAuditStore(container: container)
        self.coachAuditStore = auditStore

        let nostrAgent = CoachNostrAgentService()
        self.coachNostrAgent = nostrAgent

        let coachModel = UserDefaults.standard.string(forKey: AppPrefKey.openRouterModel)
            ?? AppConstants.defaultOpenRouterModel
        let agent = CoachAgentSession(
            repository: repository,
            macroPlanStore: planStore,
            macroDeviationStore: deviationStore,
            macroUntrackedRangeStore: untrackedStore,
            auditStore: auditStore,
            model: coachModel,
            recordMemory: { text in
                try nostrAgent.recordMemory(text: text)
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
        await notifications.scheduleEvaluatedTriggers()
        coachNostrAgent.start()
    }
}
