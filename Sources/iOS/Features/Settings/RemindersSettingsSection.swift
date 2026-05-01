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
                Toggle(isOn: $gapForming) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You haven't logged in a few days")
                        Text("Nudge after 2–3 days without a reading.")
                            .font(.footnote).foregroundStyle(Color.secondary)
                    }
                }
                .onChange(of: gapForming) { _, _ in reschedule() }
                Toggle(isOn: $gapDeepening) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're in a tracking gap")
                        Text("Alert when a gap has been going a week or longer.")
                            .font(.footnote).foregroundStyle(Color.secondary)
                    }
                }
                .onChange(of: gapDeepening) { _, _ in reschedule() }
                Toggle(isOn: $clusterBroken) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your streak ended")
                        Text("Notify when your logging streak is broken by a gap.")
                            .font(.footnote).foregroundStyle(Color.secondary)
                    }
                }
                .onChange(of: clusterBroken) { _, _ in reschedule() }
                Toggle(isOn: $cutDay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily cut check-in")
                        Text("Morning reminder while you're in an active cut.")
                            .font(.footnote).foregroundStyle(Color.secondary)
                    }
                }
                .onChange(of: cutDay) { _, _ in reschedule() }
                Toggle(isOn: $cutMilestone) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Milestone reached")
                        Text("Celebrate hitting 25%, 50%, 75%, and 100% of your cut target.")
                            .font(.footnote).foregroundStyle(Color.secondary)
                    }
                }
                .onChange(of: cutMilestone) { _, _ in reschedule() }
                Toggle(isOn: $cutStall) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cut appears to have stalled")
                        Text("Alert when progress has slowed significantly.")
                            .font(.footnote).foregroundStyle(Color.secondary)
                    }
                }
                .onChange(of: cutStall) { _, _ in reschedule() }

                DatePicker("Quiet from", selection: quietStartBinding, displayedComponents: .hourAndMinute)
                DatePicker("Quiet until", selection: quietEndBinding, displayedComponents: .hourAndMinute)

                Text("Quiet hours wrap past midnight when end is earlier than start (e.g. 10 PM → 7 AM).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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

    private var quietStartBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: quietStartHour, minute: 0, second: 0, of: Date()) ?? Date() },
            set: { quietStartHour = Calendar.current.component(.hour, from: $0); reschedule() }
        )
    }

    private var quietEndBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: quietEndHour, minute: 0, second: 0, of: Date()) ?? Date() },
            set: { quietEndHour = Calendar.current.component(.hour, from: $0); reschedule() }
        )
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
