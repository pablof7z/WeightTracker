import SwiftUI

private enum SettingsDestination: Hashable {
    case display, reminders, health, icloud, data, ai, about
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    NavigationLink(value: SettingsDestination.display) {
                        Label("Display", systemImage: "paintbrush.fill")
                    }
                    NavigationLink(value: SettingsDestination.reminders) {
                        Label("Notifications", systemImage: "bell.fill")
                    }
                }
                Section("Data") {
                    NavigationLink(value: SettingsDestination.health) {
                        Label("Apple Health", systemImage: "heart.fill")
                    }
                    NavigationLink(value: SettingsDestination.icloud) {
                        Label("iCloud", systemImage: "icloud.fill")
                    }
                    NavigationLink(value: SettingsDestination.data) {
                        Label("Data", systemImage: "cylinder.fill")
                    }
                }
                Section("Intelligence") {
                    NavigationLink(value: SettingsDestination.ai) {
                        Label("AI", systemImage: "sparkles")
                    }
                }
                Section("About") {
                    NavigationLink(value: SettingsDestination.about) {
                        Label("About", systemImage: "info.circle.fill")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .display:   DisplaySettingsView()
                case .reminders: RemindersSettingsView()
                case .health:    HealthSettingsView()
                case .icloud:    ICloudSettingsView()
                case .data:      DataSettingsView()
                case .ai:        AISettingsView()
                case .about:     AboutView()
                }
            }
        }
    }
}
