import SwiftUI

struct HealthSettingsView: View {
    var body: some View {
        Form {
            HealthSettingsSection()
        }
        .navigationTitle("Apple Health")
    }
}
