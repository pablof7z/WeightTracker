import SwiftUI

struct DisplaySettingsView: View {
    var body: some View {
        Form {
            DisplaySettingsSection()
        }
        .navigationTitle("Display")
    }
}
