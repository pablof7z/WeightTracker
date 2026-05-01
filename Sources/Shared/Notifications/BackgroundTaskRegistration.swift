import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

@MainActor
public enum BackgroundTaskRegistration {
    public static func register(
        repository: ReadingRepository,
        notifications: NotificationService,
        onRefresh: (() -> Void)? = nil
    ) {
        #if canImport(BackgroundTasks) && os(iOS)
        _ = repository
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppConstants.bgRefreshIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                onRefresh?()
                await notifications.scheduleEvaluatedTriggers()
                schedule()
                task.setTaskCompleted(success: true)
            }
        }
        schedule()
        #endif
    }

    public static func schedule() {
        #if canImport(BackgroundTasks) && os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.bgRefreshIdentifier)
        request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 12, to: Date())
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // OK to ignore — common failures: simulator (unsupported), already scheduled
        }
        #endif
    }
}
