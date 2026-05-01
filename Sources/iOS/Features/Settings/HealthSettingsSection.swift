import SwiftUI

struct HealthSettingsSection: View {
    @EnvironmentObject private var appServices: AppServices

    @AppStorage(AppPrefKey.healthKitReadEnabled) private var readEnabled: Bool = false
    @AppStorage(AppPrefKey.healthKitWriteEnabled) private var writeEnabled: Bool = false

    @State private var isReplaying = false
    @State private var replayResult: String?

    @State private var isBackfillingSleep = false
    @State private var sleepBackfillCount: Int?

    @State private var isBackfillingActivity = false
    @State private var activityBackfillCount: Int?

    var body: some View {
        Section {
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
                        Text("Re-import from Apple Health")
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
                        Label("Import past sleep", systemImage: "moon.zzz")
                        if isBackfillingSleep {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isBackfillingSleep)

                Button {
                    Task { await backfillActivity() }
                } label: {
                    HStack {
                        Label("Backfill activity history", systemImage: "figure.walk")
                        if isBackfillingActivity {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isBackfillingActivity)
            } else {
                Text("Apple Health is not available on this device.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Re-import scans Apple Health for any weight readings you logged before installing WeightTracker. Sleep and activity backfill pull the last 90 days.")
        }
        .alert("Sleep import complete", isPresented: Binding(
            get: { sleepBackfillCount != nil },
            set: { if !$0 { sleepBackfillCount = nil } }
        )) {
            Button("OK", role: .cancel) { sleepBackfillCount = nil }
        } message: {
            if let n = sleepBackfillCount {
                Text("Imported \(n) night\(n == 1 ? "" : "s") from Apple Health.")
            }
        }
        .alert("Activity backfill complete", isPresented: Binding(
            get: { activityBackfillCount != nil },
            set: { if !$0 { activityBackfillCount = nil } }
        )) {
            Button("OK", role: .cancel) { activityBackfillCount = nil }
        } message: {
            if let n = activityBackfillCount {
                Text("Imported \(n) day\(n == 1 ? "" : "s") of activity from Apple Health.")
            }
        }
    }

    private func backfillSleep() async {
        isBackfillingSleep = true
        defer { isBackfillingSleep = false }
        _ = await appServices.sleepHealthKit.requestAuthorization()
        let n = await appServices.sleepHealthKit.backfillHistory()
        appServices.cutCoach.refresh(trigger: .healthSleep)
        sleepBackfillCount = n
    }

    private func backfillActivity() async {
        isBackfillingActivity = true
        defer { isBackfillingActivity = false }
        _ = await appServices.activityHealthKit.requestAuthorization()
        let n = await appServices.activityHealthKit.backfillHistory()
        appServices.cutCoach.refresh(trigger: .healthActivity)
        activityBackfillCount = n
    }

    private func replayHistory() async {
        isReplaying = true
        defer { isReplaying = false }
        let count = await appServices.healthKit.replayHistory()
        appServices.cutCoach.refresh(trigger: .healthWeight)
        replayResult = "Imported \(count) reading\(count == 1 ? "" : "s")."
        Task {
            try? await Task.sleep(for: .seconds(5))
            replayResult = nil
        }
    }
}
