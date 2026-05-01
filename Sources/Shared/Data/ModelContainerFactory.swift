import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static func makeContainer() -> ModelContainer {
        let schema = Schema([Reading.self])
        // App Group URL for sharing with watchOS
        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
        let storeURL = groupURL?.appendingPathComponent("WeightTracker.store")

        let icloudEnabled = UserDefaults.standard.object(forKey: AppPrefKey.icloudSyncEnabled) as? Bool ?? true

        var configuration: ModelConfiguration
        if let storeURL {
            #if os(iOS)
            if icloudEnabled {
                configuration = ModelConfiguration(
                    "WeightTracker",
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .private(AppConstants.cloudKitContainerID)
                )
            } else {
                configuration = ModelConfiguration(
                    "WeightTracker",
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )
            }
            #else
            configuration = ModelConfiguration(
                "WeightTracker",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            #endif
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
            // Fallback to in-memory if persistent fails (e.g., entitlement missing in simulator)
            let mem = ModelConfiguration("WeightTrackerMemory", schema: schema, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: schema, configurations: [mem]))
                ?? (try! ModelContainer(for: schema))
        }
    }
}
