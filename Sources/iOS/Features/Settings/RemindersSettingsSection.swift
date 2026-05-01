import SwiftUI

struct RemindersSettingsSection: View {
    @EnvironmentObject private var appServices: AppServices

    @AppStorage(AppPrefKey.notifMaster) private var master: Bool = true
    @AppStorage(AppPrefKey.notifGapForming) private var gapForming: Bool = true
    @AppStorage(AppPrefKey.notifGapDeepening) private var gapDeepening: Bool = true
    @AppStorage(AppPrefKey.notifClusterBroken) private var clusterBroken: Bool = true
    @AppStorage(AppPrefKey.notifCutDay) private var cutDay: Bool = true
    @AppStorage(AppPrefKey.notifCutMilestone) private var cutMilestone: Bool = true
    @AppStorage(AppPrefKey.notifCutStall) private var cutStall: Bool = true
    @AppStorage(AppPrefKey.notifQuietStartHour) private var quietStartHour: Int = 22
    @AppStorage(AppPrefKey.notifQuietEndHour) private var quietEndHour: Int = 7

    @State private var pausedUntil: Date? = UserDefaults.standard.object(forKey: AppPrefKey.notifPausedUntil) as? Date

    var body: some View {
        Section("Notifications") {
            Toggle("Enable reminders", isOn: $master)
                .onChange(of: master) { _, _ in reschedule() }

            if master {
                Toggle("Gap forming", isOn: $gapForming)
                    .onChange(of: gapForming) { _, _ in reschedule() }
                Toggle("Gap deepening", isOn: $gapDeepening)
                    .onChange(of: gapDeepening) { _, _ in reschedule() }
                Toggle("Cluster broken", isOn: $clusterBroken)
                    .onChange(of: clusterBroken) { _, _ in reschedule() }
                Toggle("Cut day reminder", isOn: $cutDay)
                    .onChange(of: cutDay) { _, _ in reschedule() }
                Toggle("Cut milestones", isOn: $cutMilestone)
                    .onChange(of: cutMilestone) { _, _ in reschedule() }
                Toggle("Cut stall", isOn: $cutStall)
                    .onChange(of: cutStall) { _, _ in reschedule() }

                Stepper("Quiet from \(formatHour(quietStartHour))",
                        value: $quietStartHour, in: 0...23)
                    .onChange(of: quietStartHour) { _, _ in reschedule() }
                Stepper("Quiet until \(formatHour(quietEndHour))",
                        value: $quietEndHour, in: 0...23)
                    .onChange(of: quietEndHour) { _, _ in reschedule() }

                if let until = pausedUntil, until > Date() {
                    HStack {
                        Text("Paused until \(until.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Resume") { resume() }
                    }
                } else {
                    Button("Pause for today") { pauseToday() }
                }
            }
        }
    }

    private func formatHour(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        c.minute = 0
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func pauseToday() {
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
        UserDefaults.standard.set(endOfDay, forKey: AppPrefKey.notifPausedUntil)
        pausedUntil = endOfDay
        reschedule()
    }

    private func resume() {
        UserDefaults.standard.removeObject(forKey: AppPrefKey.notifPausedUntil)
        pausedUntil = nil
        reschedule()
    }

    private func reschedule() {
        Task { await appServices.notifications.scheduleEvaluatedTriggers() }
    }
}
