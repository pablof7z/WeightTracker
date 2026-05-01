import SwiftUI
import SwiftData

@main
struct WeightTrackerWatchApp: App {
    @StateObject private var watchServices = WatchServices.shared

    var body: some Scene {
        WindowGroup {
            WatchEntryView()
                .environmentObject(watchServices)
                .modelContainer(watchServices.modelContainer)
        }
    }
}

@MainActor
final class WatchServices: ObservableObject {
    static let shared = WatchServices()
    let modelContainer: ModelContainer
    let repository: ReadingRepository
    let healthKit: HealthKitManager

    private init() {
        let container = ModelContainerFactory.makeContainer()
        self.modelContainer = container
        let repo = SwiftDataReadingRepository(container: container)
        self.repository = repo
        self.healthKit = HealthKitManager(repository: repo)
    }
}
