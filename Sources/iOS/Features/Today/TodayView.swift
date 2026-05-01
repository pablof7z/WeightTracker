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
    @State private var dismissTask: Task<Void, Never>?

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

                    OptionalDetailsRow(
                        hipsValue: $viewModel.hipsValue,
                        waistValue: $viewModel.waistValue,
                        note: $viewModel.note,
                        bodyUnitSymbol: bodyUnit.symbol
                    )
                    .padding(.horizontal)

                    saveButton
                        .padding(.horizontal)

                    if let active = viewModel.activeCut, let projection = viewModel.projection {
                        ActiveCutMinichart(
                            active: active,
                            inCutReadings: viewModel.inCutReadings,
                            projection: projection,
                            unit: weightUnit
                        )
                        .padding(.horizontal)
                        .transition(.opacity)
                    }

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
            .onChange(of: viewModel.lastSaved) { _, newValue in
                dismissTask?.cancel()
                guard newValue != nil else { return }
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.lastSaved = nil
                    }
                }
            }
        }
    }

    // MARK: - Title

    private var cutDayNumber: Int? {
        guard let cut = viewModel.activeCut else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: cut.startDate)
        let day = cal.startOfDay(for: viewModel.date)
        guard day >= start else { return nil }
        let last = cal.startOfDay(for: cut.targetEndDate)
        guard day <= max(last, cal.startOfDay(for: Date())) else { return nil }
        let n = cal.dateComponents([.day], from: start, to: day).day ?? 0
        return n + 1
    }

    private var titleText: String {
        if let dayNum = cutDayNumber {
            return "Day \(dayNum)"
        }
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
        if cutDayNumber != nil {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            return fmt.string(from: viewModel.date)
        }
        return viewModel.hasEntry ? "Logged" : "No entry"
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
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.lastSaved = nil
            viewModel.loadForDate(day, repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit)
        }
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
        .sensoryFeedback(.success, trigger: viewModel.lastSaved)
    }
}

#Preview {
    TodayView()
        .environmentObject(AppServices.shared)
}
