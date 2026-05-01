import SwiftUI

struct HealthSettingsSection: View {
    @EnvironmentObject private var appServices: AppServices

    @AppStorage(AppPrefKey.healthKitReadEnabled) private var readEnabled: Bool = false
    @AppStorage(AppPrefKey.healthKitWriteEnabled) private var writeEnabled: Bool = false

    @State private var isReplaying = false
    @State private var replayResult: String?

    var body: some View {
        Section("Apple Health") {
            if appServices.healthKit.isAvailable {
                Toggle("Read from Apple Health", isOn: $readEnabled)
                    .onChange(of: readEnabled) { _, newValue in
                        if newValue {
                            Task {
                                _ = await appServices.healthKit.requestAuthorization()
                                await appServices.healthKit.startObservingIfAuthorized()
                            }
                        }
                    }
                Toggle("Write to Apple Health", isOn: $writeEnabled)
                    .onChange(of: writeEnabled) { _, newValue in
                        if newValue {
                            Task { _ = await appServices.healthKit.requestAuthorization() }
                        }
                    }

                Button {
                    Task { await replayHistory() }
                } label: {
                    HStack {
                        Text("Replay HealthKit history")
                        if isReplaying {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isReplaying || !readEnabled)

                if let replayResult {
                    Text(replayResult).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("Apple Health is not available on this device.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func replayHistory() async {
        isReplaying = true
        defer { isReplaying = false }
        let count = await appServices.healthKit.replayHistory()
        replayResult = "Imported \(count) sample\(count == 1 ? "" : "s")."
    }
}
