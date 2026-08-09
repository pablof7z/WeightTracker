import SwiftUI
import UniformTypeIdentifiers

struct ImportCSVSheet: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var didAutoPresent = false
    @State private var preview: CSVImportPreview?
    @State private var error: String?
    @State private var weightOverride: WeightUnit?
    @State private var bodyOverride: BodyUnit?
    @State private var sourceURL: URL?
    @State private var replaceExisting = true
    @State private var isImporting = false
    @State private var imported: Int?

    // Pushed onto Settings' own navigation stack (NOT presented as a nested
    // sheet). Presenting the document picker from a sheet-within-the-Settings-
    // sheet collapsed the whole stack back to Today; from a pushed view the
    // picker is a stable, independent modal.
    var body: some View {
        Group {
            if let preview {
                previewView(preview)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error).multilineTextAlignment(.center)
                    Button("Choose another file") { showPicker = true }
                        .glassButtonStyle(prominent: true)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Choose a CSV file to import your weight history.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Choose CSV File") { showPicker = true }
                        .glassButtonStyle(prominent: true)
                }
                .padding()
            }
        }
        .navigationTitle("Import CSV")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data]
        ) { result in
            handlePick(result)
        }
        // Auto-open the picker once this screen has settled after the push. The
        // "Choose CSV File" button above is the reliable fallback.
        .task {
            guard !didAutoPresent else { return }
            didAutoPresent = true
            try? await Task.sleep(for: .milliseconds(400))
            if preview == nil, sourceURL == nil, error == nil {
                showPicker = true
            }
        }
    }

    @ViewBuilder
    private func previewView(_ p: CSVImportPreview) -> some View {
        Form {
            Section("Summary") {
                row("Rows parsed", "\(p.rowCount)")
                row("Valid readings", "\(p.validReadings.count)")
                if let first = p.firstDate, let last = p.lastDate {
                    row("Date range", "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
                }
                row("Duplicates collapsed", "\(p.duplicatesCollapsed)")
                if !p.collisionDates.isEmpty {
                    row("Date collisions", "\(p.collisionDates.count)")
                }
                if !p.skippedRows.isEmpty {
                    row("Skipped rows", "\(p.skippedRows.count)")
                }
            }
            Section("Detected units") {
                Picker("Weight", selection: Binding(
                    get: { weightOverride ?? p.detectedWeightUnit },
                    set: { weightOverride = $0; reparse() }
                )) {
                    ForEach(WeightUnit.allCases, id: \.rawValue) { u in
                        Text(u.label).tag(u)
                    }
                }
                Picker("Body", selection: Binding(
                    get: { bodyOverride ?? p.detectedBodyUnit },
                    set: { bodyOverride = $0; reparse() }
                )) {
                    ForEach(BodyUnit.allCases, id: \.rawValue) { u in
                        Text(u.label).tag(u)
                    }
                }
                Text("Unit detection confidence: \(Int(p.weightUnitConfidence * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Replace existing on collision", isOn: $replaceExisting)
            } footer: {
                Text(replaceExisting
                     ? "Existing readings on the same day will be overwritten with the imported value."
                     : "Existing readings on the same day will be kept; imported rows for those days are skipped.")
            }
            if !p.skippedRows.isEmpty {
                Section("Skipped (\(p.skippedRows.count))") {
                    ForEach(p.skippedRows.prefix(20), id: \.line) { row in
                        VStack(alignment: .leading) {
                            Text("Line \(row.line)").font(.caption.monospaced())
                            Text(row.reason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                if let imported {
                    Text("Imported \(imported) reading\(imported == 1 ? "" : "s").")
                        .foregroundStyle(.green)
                }
                Button {
                    Task { await performImport(p) }
                } label: {
                    HStack {
                        Text("Import \(p.validReadings.count) reading\(p.validReadings.count == 1 ? "" : "s")")
                        if isImporting {
                            Spacer()
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: true)
                .disabled(isImporting || p.validReadings.isEmpty || imported != nil)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary) }
    }

    private func handlePick(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let err):
            error = err.localizedDescription
        case .success(let url):
            sourceURL = url
            reparse()
        }
    }

    private func reparse() {
        guard let url = sourceURL else { return }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            let p = try CSVImporter.parse(
                url: url,
                weightUnitOverride: weightOverride,
                bodyUnitOverride: bodyOverride
            )
            preview = p
            error = nil
        } catch {
            self.error = error.localizedDescription
            preview = nil
        }
    }

    private func performImport(_ p: CSVImportPreview) async {
        isImporting = true
        defer { isImporting = false }
        appServices.repository.bulkInsert(p.validReadings, replacingExisting: replaceExisting)
        imported = p.validReadings.count
        await appServices.notifications.scheduleEvaluatedTriggers()
    }
}
