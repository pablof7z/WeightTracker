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

    @Published var lastSyncDate: Date?

    private init() {
        let container = ModelContainerFactory.makeContainer()
        self.modelContainer = container
        self.repository = SwiftDataReadingRepository(container: container)
        self.healthKit = HealthKitManager(repository: repository)
        self.notifications = NotificationService(repository: repository)
        self.sleepHealthKit = SleepHealthKit(repository: repository)
    }

    func bootstrap() async {
        // Don't auto-request notification permission — let onboarding/Settings ask explicitly.
        await healthKit.startObservingIfAuthorized()
        await sleepHealthKit.startObservingIfAuthorized()
        await notifications.scheduleEvaluatedTriggers()
    }
}
