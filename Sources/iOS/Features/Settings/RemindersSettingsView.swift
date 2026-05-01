import SwiftUI

struct RemindersSettingsView: View {
    var body: some View {
        Form {
            RemindersSettingsSection()
        }
        .navigationTitle("Notifications")
    }
}
