import SwiftUI
import SwiftData

struct TodayView: View {
    @EnvironmentObject var services: AppServices
    @StateObject private var viewModel = TodayViewModel()

    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue

    @State private var didLoad = false
    @State private var isSaving = false
    @State private var showDatePicker = false
    @State private var swipeAccum: CGFloat = 0

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }
    private var bodyUnit: BodyUnit { BodyUnit(rawValue: bodyUnitRaw) ?? .inches }

    private var canGoForward: Bool {
        Calendar.current.startOfDay(for: viewModel.date) < Calendar.current.startOfDay(for: Date())
    }
    private var canGoBack: Bool {
        viewModel.date > viewModel.minDate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    NumericPad(
                        value: $viewModel.displayValue,
                        unitSymbol: weightUnit.symbol,
                        onUnitTap: toggleUnit
                    )
                    .opacity(viewModel.hasEntry ? 1.0 : 0.45)
                    .padding(.top, 16)

                    if !viewModel.hasEntry {
                        placeholderHint
                    }

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
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(swipeGesture)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        showDatePicker = true
                    } label: {
                        VStack(spacing: 0) {
                            Text(titleText)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(subtitleText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Selected date \(titleText). Tap to pick a date.")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if canGoBack { goBack() }
                    } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if canGoForward { goForward() }
                    } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    DatePicker(
                        "Select date",
                        selection: Binding(
                            get: { viewModel.date },
                            set: { selectDate($0) }
                        ),
                        in: viewModel.minDate...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Jump to date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDatePicker = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                if !didLoad {
                    viewModel.loadForDate(Date(), repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit)
                    didLoad = true
                }
            }
            .onChange(of: weightUnitRaw) { _, _ in
                viewModel.loadForDate(viewModel.date, repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit)
            }
        }
    }

    // MARK: - Title

    private var titleText: String {
        let cal = Calendar.current
        if cal.isDateInToday(viewModel.date) { return "Today" }
        if cal.isDateInYesterday(viewModel.date) { return "Yesterday" }
        let daysAgo = cal.dateComponents([.day], from: viewModel.date, to: Date()).day ?? 0
        if daysAgo > 0 && daysAgo < 7 {
            let fmt = DateFormatter()
            fmt.dateFormat = "EEEE"
            return fmt.string(from: viewModel.date)
        }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: viewModel.date)
    }

    private var subtitleText: String {
        if viewModel.hasEntry { return "Logged" }
        return "No entry"
    }

    // MARK: - Date navigation

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                if dx <= -50, canGoForward {
                    goForward()
                } else if dx >= 50, canGoBack {
                    goBack()
                }
            }
    }

    private func goBack() {
        let prev = Calendar.current.date(byAdding: .day, value: -1, to: viewModel.date) ?? viewModel.date
        selectDate(prev)
    }

    private func goForward() {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: viewModel.date) ?? viewModel.date
        selectDate(next)
    }

    private func selectDate(_ d: Date) {
        let day = Reading.dayStart(of: d)
        guard day != viewModel.date else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.loadForDate(day, repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit)
        }
    }

    // MARK: - UI helpers

    private var placeholderHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("No entry on this date — tap Save to add")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glass(in: Capsule())
    }

    private func toggleUnit() {
        let next: WeightUnit = (weightUnit == .lbs) ? .kg : .lbs
        let kg = UnitConvert.storeWeight(viewModel.displayValue, from: weightUnit)
        viewModel.displayValue = (UnitConvert.displayWeight(kg: kg, in: next) * 10.0).rounded() / 10.0
        weightUnitRaw = next.rawValue
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
                if isSaving { ProgressView() }
                Text(isSaving ? "Saving…" : (viewModel.hasEntry ? "Update" : "Save"))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glass(in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.primary)
        }
        .disabled(isSaving)
    }
}

#Preview {
    TodayView()
        .environmentObject(AppServices.shared)
}
