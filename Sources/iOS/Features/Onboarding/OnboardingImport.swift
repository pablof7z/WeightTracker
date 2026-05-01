import SwiftUI
import UniformTypeIdentifiers

struct OnboardingImport: View {
    @EnvironmentObject private var appServices: AppServices

    @State private var showPicker = false
    @State private var preview: CSVImportPreview?
    @State private var error: String?
    @State private var imported: Int?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Bring your history")
                .font(.title.bold())
            Text("Import a CSV with `Date,Hips,Waist,Weight`. Already have it elsewhere? Pull it in now.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if let preview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(preview.validReadings.count) readings ready")
                        .font(.headline)
                    if let first = preview.firstDate, let last = preview.lastDate {
                        Text("\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Detected: \(preview.detectedWeightUnit.label) / \(preview.detectedBodyUnit.label)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                if let imported {
                    Text("Imported \(imported) readings.").foregroundStyle(.green)
                } else {
                    Button {
                        Task { await performImport(preview) }
                    } label: {
                        HStack {
                            Text("Import \(preview.validReadings.count) readings")
                            if isImporting { ProgressView() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isImporting)
                }
            } else if let error {
                Text(error).foregroundStyle(.red).padding(.horizontal)
            }

            Button("Pick a CSV file") { showPicker = true }
                .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data]
        ) { result in
            handlePick(result)
        }
    }

    private func handlePick(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let err):
            error = err.localizedDescription
        case .success(let url):
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                preview = try CSVImporter.parse(url: url)
                error = nil
            } catch {
                self.error = error.localizedDescription
                preview = nil
            }
        }
    }

    private func performImport(_ p: CSVImportPreview) async {
        isImporting = true
        defer { isImporting = false }
        appServices.repository.bulkInsert(p.validReadings, replacingExisting: true)
        appServices.cutCoach.refresh(trigger: .weightSaved)
        imported = p.validReadings.count
    }
}
