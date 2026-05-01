import SwiftUI

struct LLMSettingsView: View {
    @AppStorage(AppPrefKey.openRouterModel) private var openRouterModel: String = AppConstants.defaultOpenRouterModel
    @State private var connection = OpenRouterCredentialStore.loadConnection()
    @State private var connector = BYOKOpenRouterConnector()
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var modelSelectorPresented = false

    var body: some View {
        Form {
            Section {
                Button {
                    modelSelectorPresented = true
                } label: {
                    modelRow(modelID: openRouterModel, label: "Agent model")
                }
                .buttonStyle(.plain)
            } header: {
                Text("Model")
            }

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
        .sheet(isPresented: $modelSelectorPresented) {
            NavigationStack {
                OpenRouterModelSelectorView(selectedModelID: $openRouterModel)
            }
            .presentationDragIndicator(.visible)
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

    private func modelRow(modelID: String, label: String) -> some View {
        HStack(spacing: 12) {
            ProviderLogoView(
                providerID: providerID(for: modelID),
                providerName: providerName(for: modelID)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(modelID)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func providerID(for modelID: String) -> String {
        modelID.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "openrouter"
    }

    private func providerName(for modelID: String) -> String {
        providerID(for: modelID)
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
