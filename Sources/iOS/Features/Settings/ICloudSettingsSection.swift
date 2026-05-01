import SwiftUI

struct ICloudSettingsSection: View {
    @AppStorage(AppPrefKey.icloudSyncEnabled) private var syncEnabled: Bool = true

    var body: some View {
        Section {
            Toggle("Sync with iCloud", isOn: $syncEnabled)
        } header: {
            Text("iCloud")
        } footer: {
            Text("Syncs your readings, cuts, and macro plans across devices signed in to the same iCloud account. Settings and HealthKit cache stay on this device.")
        }
    }
}
