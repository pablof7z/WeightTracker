import SwiftUI

struct AISettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    LLMSettingsView()
                } label: {
                    Label("LLM", systemImage: "text.bubble.fill")
                }
                NavigationLink {
                    ElevenLabsSettingsView()
                } label: {
                    Label("ElevenLabs", systemImage: "waveform")
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("AI powers the cut coach and voice check-ins.")
            }

            Section {
                NavigationLink {
                    UsageCostSettingsView()
                } label: {
                    Label("Cost", systemImage: "dollarsign.circle.fill")
                }
            } header: {
                Text("Usage")
            }
        }
        .navigationTitle("AI")
    }
}
