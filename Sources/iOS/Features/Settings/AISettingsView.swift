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
            }
        }
        .navigationTitle("AI")
    }
}
