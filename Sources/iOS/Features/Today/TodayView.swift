import SwiftUI
import SwiftData

struct TodayView: View {
    @EnvironmentObject var services: AppServices
    @StateObject private var viewModel = TodayViewModel()

    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue

    @State private var didPrefill = false
    @State private var isSaving = false

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }
    private var bodyUnit: BodyUnit { BodyUnit(rawValue: bodyUnitRaw) ?? .inches }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    NumericPad(
                        value: $viewModel.displayValue,
                        unitSymbol: weightUnit.symbol
                    )
                    .padding(.top, 16)

                    dateChip

                    OptionalDetailsRow(
                        hipsValue: $viewModel.hipsValue,
                        waistValue: $viewModel.waistValue,
                        note: $viewModel.note,
                        bodyUnitSymbol: bodyUnit.symbol
                    )
                    .padding(.horizontal)

                    saveButton
                        .padding(.horizontal)

                    if let saved = viewModel.lastSaved {
                        ConfirmationCard(confirmation: saved) {
                            withAnimation { viewModel.lastSaved = nil }
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("Today")
            .onAppear {
                if !didPrefill {
                    viewModel.prefill(from: services.repository, unit: weightUnit)
                    didPrefill = true
                }
            }
            .onChange(of: weightUnitRaw) { _, _ in
                viewModel.prefill(from: services.repository, unit: weightUnit)
            }
        }
    }

    private var dateChip: some View {
        DatePicker(
            "Date",
            selection: $viewModel.date,
            in: viewModel.minDate...Date(),
            displayedComponents: .date
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glass(in: Capsule())
    }

    private var saveButton: some View {
        Button {
            Task {
                isSaving = true
                await viewModel.save(services: services, weightUnit: weightUnit, bodyUnit: bodyUnit)
                isSaving = false
            }
        } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Text(isSaving ? "Saving..." : "Save")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glass(in: RoundedRectangle(cornerRadius: 14), tint: .accentColor)
            .foregroundStyle(.white)
        }
        .disabled(isSaving)
    }
}

#Preview {
    TodayView()
        .environmentObject(AppServices.shared)
}
