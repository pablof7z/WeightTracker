import Foundation

#if DEBUG
/// QA hook: pass `-SeedCSVPath <path>` as a launch argument to import a CSV
/// through the same `CSVImporter` + `bulkInsert` path `ImportCSVSheet` uses,
/// without driving the system file picker (useful for simulator automation).
enum DebugCSVSeeder {
    @MainActor
    static func seedIfRequested(services: AppServices) {
        guard let path = UserDefaults.standard.string(forKey: "SeedCSVPath") else { return }
        let url = URL(fileURLWithPath: path)
        guard let preview = try? CSVImporter.parse(url: url) else { return }
        services.repository.bulkInsert(preview.validReadings, replacingExisting: true)
    }
}
#endif
