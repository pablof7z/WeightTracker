import SwiftUI

struct WeightLogView: View {
    @EnvironmentObject var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue

    @State private var readings: [Reading] = []
    @State private var editing: Reading?

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }

    private static let rowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                ForEach(readings, id: \.id) { reading in
                    Button {
                        editing = reading
                    } label: {
                        row(for: reading)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    // Capture date+value BEFORE deleting (the SwiftData object is
                    // invalidated by delete), then remove the matching Apple
                    // Health sample we wrote so it doesn't linger / re-import.
                    let targets = offsets.map { (kg: readings[$0].weightKg, date: readings[$0].date) }
                    for index in offsets {
                        services.repository.delete(readings[index])
                    }
                    reload()
                    Task { @MainActor in
                        for t in targets {
                            await services.healthKit.deleteSample(weightKg: t.kg, on: t.date)
                        }
                    }
                }
            }
            .navigationTitle("Weight Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { reading in
                EditReadingSheet(reading: reading, weightUnit: weightUnit) {
                    reload()
                }
                .presentationDetents([.height(260)])
            }
            .onAppear { reload() }
        }
    }

    @ViewBuilder
    private func row(for reading: Reading) -> some View {
        let display = UnitConvert.displayWeight(kg: reading.weightKg, in: weightUnit)
        HStack {
            Text(Self.rowDateFormatter.string(from: reading.date))
                .foregroundStyle(.primary)
            Spacer()
            Text(String(format: "%.1f %@", display, weightUnit.symbol))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func reload() {
        readings = services.repository.allReadings().sorted { $0.date > $1.date }
    }
}

private struct EditReadingSheet: View {
    @EnvironmentObject var services: AppServices
    @Environment(\.dismiss) private var dismiss

    let reading: Reading
    let weightUnit: WeightUnit
    let onSaved: () -> Void

    @State private var displayValue: Double

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    init(reading: Reading, weightUnit: WeightUnit, onSaved: @escaping () -> Void) {
        self.reading = reading
        self.weightUnit = weightUnit
        self.onSaved = onSaved
        let display = UnitConvert.displayWeight(kg: reading.weightKg, in: weightUnit)
        _displayValue = State(initialValue: (display * 10.0).rounded() / 10.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(Self.dateFormatter.string(from: reading.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    Button {
                        adjust(by: -0.1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.title2.weight(.semibold))
                            .frame(width: 56, height: 56)
                    }
                    .glass(in: Circle())

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", displayValue))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(weightUnit.symbol)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 140)

                    Button {
                        adjust(by: 0.1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .frame(width: 56, height: 56)
                    }
                    .glass(in: Circle())
                }

                Button {
                    persist()
                } label: {
                    Text("Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .navigationTitle("Edit reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func adjust(by amount: Double) {
        displayValue = ((displayValue + amount) * 10.0).rounded() / 10.0
    }

    private func persist() {
        let kg = UnitConvert.storeWeight(displayValue, from: weightUnit)
        let oldKg = reading.weightKg
        let day = reading.date
        reading.weightKg = kg
        services.repository.update(reading)
        Task { @MainActor in
            // Remove the stale Health sample for the previous value before
            // writing the new one, so an edit doesn't leave a ghost behind.
            if abs(oldKg - kg) > 0.0001 {
                await services.healthKit.deleteSample(weightKg: oldKg, on: day)
            }
            await services.healthKit.writeReading(reading)
        }
        onSaved()
        dismiss()
    }
}
