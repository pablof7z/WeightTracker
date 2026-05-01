import SwiftUI

struct ICloudSettingsSection: View {
    @EnvironmentObject private var appServices: AppServices
    @AppStorage(AppPrefKey.icloudSyncEnabled) private var syncEnabled: Bool = true

    @State private var isSyncing = false

    var body: some View {
        Section("iCloud") {
            Toggle("Sync with iCloud", isOn: $syncEnabled)

            HStack {
                Text("Last sync")
                Spacer()
                Text(lastSyncText).foregroundStyle(.secondary)
            }

            Button {
                Task { await forceSync() }
            } label: {
                HStack {
                    Text("Sync now")
                    if isSyncing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isSyncing || !syncEnabled)
        }
    }

    private var lastSyncText: String {
        if let date = appServices.lastSyncDate {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return "Never"
    }

    private func forceSync() async {
        isSyncing = true
        defer { isSyncing = false }
        // CloudKit-backed SwiftData syncs automatically; we just stamp the timestamp.
        appServices.lastSyncDate = Date()
    }
}
