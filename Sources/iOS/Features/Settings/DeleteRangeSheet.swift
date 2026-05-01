import SwiftUI

struct DeleteRangeSheet: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var didDelete = false
    @State private var deletedCount: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Range") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }
                Section {
                    Text("Will delete \(matchingCount) reading\(matchingCount == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Delete readings in range", role: .destructive) {
                        performDelete()
                    }
                    .disabled(matchingCount == 0 || startDate > endDate)
                }
                if didDelete {
                    Section {
                        Text("Deleted \(deletedCount) reading\(deletedCount == 1 ? "" : "s").")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Delete date range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didDelete ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private var range: ClosedRange<Date> {
        let lo = Reading.dayStart(of: min(startDate, endDate))
        let hi = Reading.dayStart(of: max(startDate, endDate))
        return lo...hi
    }

    private var matchingCount: Int {
        appServices.repository.readings(in: range).count
    }

    private func performDelete() {
        let count = matchingCount
        appServices.repository.deleteRange(range)
        deletedCount = count
        didDelete = true
        Task { await appServices.notifications.scheduleEvaluatedTriggers() }
    }
}
