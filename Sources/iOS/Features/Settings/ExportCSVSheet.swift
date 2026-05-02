import SwiftUI
import UniformTypeIdentifiers

struct ExportCSVSheet: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue

    @State private var fileURL: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Export") {
                    Text("\(readings.count) reading\(readings.count == 1 ? "" : "s")")
                    Text("Units: \(weightUnit.label) / \(bodyUnit.label)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let fileURL {
                    Section {
                        ShareLink(item: fileURL) {
                            Label("Share CSV", systemImage: "square.and.arrow.up")
                        }
                        Text(fileURL.lastPathComponent)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Try again") { generate() }
                    }
                } else if readings.isEmpty {
                    Section {
                        Text("No data to export yet. Log a weight in the Today tab first.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Button {
                            generate()
                        } label: {
                            Text("Generate CSV")
                                .frame(maxWidth: .infinity)
                        }
                        .glassButtonStyle(prominent: true)
                    } footer: {
                        Text("Creates a plain-text file with all \(readings.count) entries. Includes date, weight, body measurements, source, and notes.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Export CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }
    private var bodyUnit: BodyUnit { BodyUnit(rawValue: bodyUnitRaw) ?? .inches }

    private var readings: [Reading] { appServices.repository.allReadings() }

    private func generate() {
        let r = readings
        guard !r.isEmpty else {
            error = "No readings to export."
            return
        }
        let text = CSVExporter.makeCSVText(readings: r, weightUnit: weightUnit, bodyUnit: bodyUnit)
        let filename = CSVExporter.suggestedFilename(for: r)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            fileURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
