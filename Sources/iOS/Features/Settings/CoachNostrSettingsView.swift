import SwiftUI

struct CoachNostrSettingsView: View {
    @EnvironmentObject private var services: AppServices

    @State private var enabled = CoachNostrAgentSettings.load().enabled
    @State private var relayURL = CoachNostrAgentSettings.load().relayURL
    @State private var keyPair: NostrKeyPair?
    @State private var statusText: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in saveAndRestart() }

                TextField("Relay", text: $relayURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(saveAndRestart)

                Button("Save relay") {
                    saveAndRestart()
                }
            } header: {
                Text("Relay")
            }

            Section {
                if let keyPair {
                    LabeledContent("Public key", value: keyPair.npub)
                        .font(.caption)
                        .textSelection(.enabled)
                    LabeledContent("Hex", value: keyPair.publicKeyHex)
                        .font(.caption)
                        .textSelection(.enabled)
                } else {
                    Text("No local coach key.")
                        .foregroundStyle(.secondary)
                }

                Button(keyPair == nil ? "Generate key" : "Replace key") {
                    generateKey()
                }

                if keyPair != nil {
                    Button("Delete key", role: .destructive) {
                        NostrCredentialStore.delete()
                        reloadKey()
                        services.coachNostrAgent.stop()
                    }
                }
            } header: {
                Text("Identity")
            } footer: {
                Text("The coach agent signs kind:1 replies with this local key.")
            }

            if let statusText {
                Section {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Nostr Coach")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadKey()
            updateStatusText()
        }
        .onReceive(services.coachNostrAgent.$status) { _ in
            updateStatusText()
        }
    }

    private func generateKey() {
        do {
            keyPair = try NostrCredentialStore.generateAndSave()
            saveAndRestart()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func reloadKey() {
        keyPair = try? NostrCredentialStore.loadKeyPair()
    }

    private func saveAndRestart() {
        var settings = CoachNostrAgentSettings.load()
        settings.enabled = enabled
        settings.relayURL = relayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CoachNostrAgentSettings.defaultRelayURL
            : relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.save()
        services.coachNostrAgent.start(settings: settings)
        updateStatusText()
    }

    private func updateStatusText() {
        switch services.coachNostrAgent.status {
        case .idle:
            statusText = "Idle"
        case .missingCredentials:
            statusText = "Missing local key"
        case .starting:
            statusText = "Starting"
        case .running(let relayURL):
            statusText = "Running on \(relayURL)"
        case .backingOff(let error):
            statusText = "Reconnecting: \(error)"
        case .error(let message):
            statusText = message
        }
    }
}
