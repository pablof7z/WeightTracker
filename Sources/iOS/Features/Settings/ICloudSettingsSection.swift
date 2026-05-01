import SwiftUI

struct ICloudSettingsSection: View {
    @AppStorage(AppPrefKey.icloudSyncEnabled) private var syncEnabled: Bool = true

    var body: some View {
        Section("iCloud") {
            Toggle("Sync with iCloud", isOn: $syncEnabled)
        }
    }
}
