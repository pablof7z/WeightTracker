import SwiftUI

struct HealthSettingsSection: View {
    @EnvironmentObject private var appServices: AppServices

    @AppStorage(AppPrefKey.healthKitReadEnabled) private var readEnabled: Bool = false
    @AppStorage(AppPrefKey.healthKitWriteEnabled) private var writeEnabled: Bool = false

    @State private var isReplaying = false
    @State private var replayResult: String?

    @State private var isBackfillingSleep = false
    @State private var sleepBackfillCount: Int?

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

                Button {
                    Task { await backfillSleep() }
                } label: {
                    HStack {
                        Label("Backfill sleep history", systemImage: "moon.zzz")
                        if isBackfillingSleep {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isBackfillingSleep)
            } else {
                Text("Apple Health is not available on this device.")
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Sleep backfill complete", isPresented: Binding(
            get: { sleepBackfillCount != nil },
            set: { if !$0 { sleepBackfillCount = nil } }
        )) {
            Button("OK", role: .cancel) { sleepBackfillCount = nil }
        } message: {
            if let n = sleepBackfillCount {
                Text("Imported \(n) night\(n == 1 ? "" : "s") from Apple Health.")
            }
        }
    }

    private func backfillSleep() async {
        isBackfillingSleep = true
        defer { isBackfillingSleep = false }
        _ = await appServices.sleepHealthKit.requestAuthorization()
        let n = await appServices.sleepHealthKit.backfillHistory()
        sleepBackfillCount = n
    }

    private func replayHistory() async {
        isReplaying = true
        defer { isReplaying = false }
        let count = await appServices.healthKit.replayHistory()
        replayResult = "Imported \(count) sample\(count == 1 ? "" : "s")."
    }
}
