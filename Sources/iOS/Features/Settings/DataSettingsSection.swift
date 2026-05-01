import SwiftUI

struct DataSettingsSection: View {
    @EnvironmentObject private var appServices: AppServices

    @AppStorage(AppPrefKey.autoExportEnabled) private var autoExportEnabled: Bool = false

    @State private var showImport = false
    @State private var showExport = false
    @State private var showDeleteRange = false
    @State private var showWipe = false

    var body: some View {
        Section("Data") {
            Button("Import CSV") { showImport = true }
            Button("Export CSV") { showExport = true }
            Toggle("Daily auto-export", isOn: $autoExportEnabled)
            Button("Delete date range...", role: .destructive) { showDeleteRange = true }
            Button("Wipe all data...", role: .destructive) { showWipe = true }
        }
        .sheet(isPresented: $showImport) {
            ImportCSVSheet()
                .environmentObject(appServices)
        }
        .sheet(isPresented: $showExport) {
            ExportCSVSheet()
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
