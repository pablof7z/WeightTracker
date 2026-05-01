import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                DisplaySettingsSection()
                RemindersSettingsSection()
                HealthSettingsSection()
                ICloudSettingsSection()
                DataSettingsSection()
                AboutSection()
            }
            .navigationTitle("Settings")
        }
    }
}
