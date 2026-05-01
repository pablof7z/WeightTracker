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
                NavigationLink {
                    CoachNostrSettingsView()
                } label: {
                    Label("Nostr Coach", systemImage: "antenna.radiowaves.left.and.right")
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("AI powers the cut coach, voice check-ins, and Nostr sharing features.")
            }
        }
        .navigationTitle("AI")
    }
}
