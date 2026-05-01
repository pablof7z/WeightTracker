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

    @Published var lastSyncDate: Date?

    private init() {
        let container = ModelContainerFactory.makeContainer()
        self.modelContainer = container
        self.repository = SwiftDataReadingRepository(container: container)
        self.healthKit = HealthKitManager(repository: repository)
        self.notifications = NotificationService(repository: repository)
    }

    func bootstrap() async {
        await notifications.requestAuthorizationIfNeeded()
        await healthKit.startObservingIfAuthorized()
        await notifications.scheduleEvaluatedTriggers()
    }
}
