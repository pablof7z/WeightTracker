import SwiftUI

struct ElevenLabsSettingsView: View {
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel: String = AppConstants.defaultElevenLabsSTTModel

    @State private var connection = ElevenLabsCredentialStore.loadConnection()
    @State private var connector = BYOKElevenLabsConnector()
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private var hasLegacyKey: Bool {
        connection == nil && ElevenLabsCredentialStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        Form {
            Section {
                if let connection {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    LabeledContent("Key", value: connection.keyLabel)
                    LabeledContent("Connected", value: connection.connectedAt.formatted(date: .abbreviated, time: .shortened))
                } else if hasLegacyKey {
                    Text("A local ElevenLabs key is present. Reconnect with BYOK to replace it.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No ElevenLabs key is connected.")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text(connection == nil && !hasLegacyKey ? "Connect with BYOK" : "Reconnect with BYOK")
                        if isConnecting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isConnecting)

                if connection != nil || hasLegacyKey {
                    Button("Disconnect ElevenLabs", role: .destructive) {
                        ElevenLabsCredentialStore.delete()
                        connection = nil
                        errorMessage = nil
                    }
                }
            } header: {
                Text("ElevenLabs")
            } footer: {
                Text("BYOK lets you choose a labeled ElevenLabs key and returns it to this app once. The key is stored in Keychain for voice check-in transcription.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Transcription") {
                TextField("Realtime STT model", text: $sttModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("ElevenLabs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            connection = ElevenLabsCredentialStore.loadConnection()
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            connection = try await connector.connect()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
