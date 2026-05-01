import SwiftUI

struct OnboardingReminders: View {
    @EnvironmentObject private var appServices: AppServices

    @AppStorage(AppPrefKey.notifMaster) private var master: Bool = true
    @State private var status: String?
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("Quiet, useful nudges")
                .font(.title.bold())
            Text("Only when a tracking gap forms or your active cut needs attention. No daily noise.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Toggle("Enable reminders", isOn: $master)
                .padding(.horizontal)

            Button {
                Task { await request() }
            } label: {
                HStack {
                    Text("Allow notifications")
                    if isRequesting { ProgressView() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting || !master || status?.contains("allowed") == true)

            if let status {
                Text(status).font(.footnote).foregroundStyle(.secondary)
                if status.contains("denied") {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote)
                    Text("You can enable this anytime in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
    }

    private func request() async {
        isRequesting = true
        defer { isRequesting = false }
        let granted = await appServices.notifications.requestAuthorization()
        status = granted ? "Notifications allowed." : "Notifications denied."
        if granted {
            await appServices.notifications.scheduleEvaluatedTriggers()
        }
    }
}
