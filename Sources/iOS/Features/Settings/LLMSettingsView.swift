import SwiftUI

struct LLMSettingsView: View {
    @State private var connection = OpenRouterCredentialStore.loadConnection()
    @State private var connector = BYOKOpenRouterConnector()
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if let connection {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    LabeledContent("Key", value: connection.keyLabel)
                    LabeledContent("Connected", value: connection.connectedAt.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("No OpenRouter key is connected.")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text(connection == nil ? "Connect with BYOK" : "Reconnect with BYOK")
                        if isConnecting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isConnecting)

                if connection != nil {
                    Button("Disconnect OpenRouter", role: .destructive) {
                        OpenRouterCredentialStore.delete()
                        connection = nil
                        errorMessage = nil
                    }
                }
            } header: {
                Text("OpenRouter")
            } footer: {
                Text("BYOK lets you choose a labeled OpenRouter key and returns it to this app once. The key is stored in Keychain.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("LLM")
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
