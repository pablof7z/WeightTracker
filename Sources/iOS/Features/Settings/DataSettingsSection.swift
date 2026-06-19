import SwiftUI

struct DataSettingsSection: View {
    @EnvironmentObject private var appServices: AppServices

    @AppStorage(AppPrefKey.autoExportEnabled) private var autoExportEnabled: Bool = false

    @State private var showImport = false
    @State private var showDeleteRange = false
    @State private var showWipe = false

    var body: some View {
        Section {
            Button("Import CSV") { showImport = true }
            NavigationLink("Export CSV") {
                ExportCSVSheet()
            }
            Toggle("Auto-export daily", isOn: $autoExportEnabled)
            Button("Delete date range…", role: .destructive) { showDeleteRange = true }
            Button("Wipe all data…", role: .destructive) { showWipe = true }
        } header: {
            Text("Data")
        } footer: {
            Text("Deletes readings, sleep, and macro history. iCloud copies on other devices will sync the deletion.")
        }
        .sheet(isPresented: $showImport) {
            ImportCSVSheet()
                .environmentObject(appServices)
        }
        .sheet(isPresented: $showDeleteRange) {
            DeleteRangeSheet()
                .environmentObject(appServices)
        }
        .sheet(isPresented: $showWipe) {
            WipeAllSheet()
                .environmentObject(appServices)
        }
    }
}
