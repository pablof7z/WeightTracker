import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Reading.self,
            SleepNight.self,
            DailyActivity.self,
            MacroPlanPeriod.self,
            MacroDeviation.self,
            MacroUntrackedRange.self,
            CoachRun.self,
            CoachNote.self,
            CoachToolCall.self,
        ])
        // App Group URL for sharing with watchOS
        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
        let storeURL = groupURL?.appendingPathComponent("WeightTracker.store")

        // CloudKit sync deferred to v1.1 — requires the iCloud.app.pfer.weighttracker
        // container to be provisioned in the developer portal first.
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(
                "WeightTracker",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "WeightTracker",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            print("[ModelContainerFactory] persistent container failed: \(error). Falling back to in-memory.")
            let mem = ModelConfiguration("WeightTrackerMemory", schema: schema, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: schema, configurations: [mem]))
                ?? (try! ModelContainer(for: schema))
        }
    }
}
