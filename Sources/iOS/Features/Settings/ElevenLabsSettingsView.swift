import SwiftUI

struct ElevenLabsSettingsView: View {
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel: String = AppConstants.defaultElevenLabsSTTModel

    @State private var apiKey = ElevenLabsCredentialStore.loadAPIKey() ?? ""
    @State private var savedMessage: String?

    private var hasStoredKey: Bool {
        ElevenLabsCredentialStore.loadAPIKey()?.isEmpty == false
    }

    var body: some View {
        Form {
            Section {
                Label(
                    hasStoredKey ? "Local key stored" : "No local key stored",
                    systemImage: hasStoredKey ? "checkmark.seal.fill" : "key"
                )
                .foregroundStyle(hasStoredKey ? Color.accentColor : Color.secondary)

                SecureField("ElevenLabs API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Save API key") {
                    ElevenLabsCredentialStore.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    flash("Saved")
                }
                .buttonStyle(.bordered)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if hasStoredKey {
                    Button("Clear API key", role: .destructive) {
                        ElevenLabsCredentialStore.delete()
                        apiKey = ""
                        flash("Cleared")
                    }
                }

                if let savedMessage {
                    Text(savedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("API key")
            } footer: {
                Text("The key is stored in Keychain on this device and used for voice check-in transcription.")
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
            apiKey = ElevenLabsCredentialStore.loadAPIKey() ?? ""
        }
    }

    private func flash(_ message: String) {
        savedMessage = message
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                if savedMessage == message {
                    savedMessage = nil
                }
            }
        }
    }
}
