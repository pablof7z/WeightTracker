import SwiftUI

struct OnboardingHealth: View {
    @EnvironmentObject private var appServices: AppServices

    @AppStorage(AppPrefKey.healthKitReadEnabled) private var readEnabled: Bool = false
    @AppStorage(AppPrefKey.healthKitWriteEnabled) private var writeEnabled: Bool = false

    @State private var status: String?
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .font(.system(size: 64))
                .foregroundStyle(.pink)
            Text("Connect Apple Health")
                .font(.title.bold())
            Text("Read weights from your scale or Apple Watch, and write the ones you log here back to Apple Health.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if appServices.healthKit.isAvailable {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text("Connect Apple Health")
                        if isRequesting { ProgressView() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)

                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("Apple Health is not available on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func connect() async {
        isRequesting = true
        defer { isRequesting = false }
        let granted = await appServices.healthKit.requestAuthorization()
        if granted {
            readEnabled = true
            writeEnabled = true
            await appServices.healthKit.startObservingIfAuthorized()
            status = "Connected to Apple Health."
        } else {
            status = "Authorization denied or unavailable."
        }
    }
}
