import SwiftUI
import SwiftData

struct TodayView: View {
    @EnvironmentObject var services: AppServices
    @StateObject private var viewModel = TodayViewModel()

    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel: String = AppConstants.defaultElevenLabsSTTModel
    /// The Today carousel arrangement the user configured in Settings.
    @AppStorage(AppPrefKey.todayLensOrder) private var lensOrderRaw: String = ""
    @AppStorage(AppPrefKey.todayLensHidden) private var lensHiddenRaw: String = ""

    /// `.compact` vertical size class on iPhone == landscape. Drives the
    /// portrait/landscape body swap on the Today tab. We allow the actual
    /// rotation to happen by widening `AppOrientation.shared.supportedMask`
    /// in `.onAppear` (and reverting it in `.onDisappear`).
    @Environment(\.verticalSizeClass) private var vSizeClass

    @StateObject private var cutsVM = CutsViewModel()
    @State private var didLoad = false
    @State private var showDatePicker = false
    @State private var showSettings = false
    @State private var showConversations = false
    @State private var autoRecordConversations = false
    @State private var showStartSheet = false
    @State private var showEditSheet = false
    @State private var showCutHistory = false
    @State private var showMealPlanEditor = false
    @ObservedObject private var pinnedNoteStore = TodayPinnedNoteStore.shared
    @State private var dismissTask: Task<Void, Never>?
    @State private var weightInputActive = false
    /// The active Today lens. Not persisted: every cold launch opens on Current
    /// Weight, but the selection is retained while the app stays alive.
    @State private var lensSelection: TodayLens = .launchDefault
    @State private var showLogSheet = false
    @State private var showDetailChart = false

    private var isLandscape: Bool { vSizeClass == .compact }

    /// The enabled lenses in the saved order. Guaranteed non-empty: hiding every
    /// lens falls back to Current Weight rather than an empty carousel.
    private var enabledLenses: [TodayLens] {
        TodayLensOrder.enabled(orderRaw: lensOrderRaw, hiddenRaw: lensHiddenRaw)
    }

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }
    private var bodyUnit: BodyUnit { BodyUnit(rawValue: bodyUnitRaw) ?? .inches }

    /// Subtitle showing the 7-day EMA in the active display unit, or "—" when not enough history.
    private var emaSubtitle: String {
        guard let kg = viewModel.ema7Kg else { return "7-day avg —" }
        let display = UnitConvert.displayWeight(kg: kg, in: weightUnit)
        return String(format: "7-day avg %.1f %@", display, weightUnit.symbol)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLandscape {
                    landscapeContent
                        .toolbar(.hidden, for: .tabBar)
                        .toolbar(.hidden, for: .navigationBar)
                        .statusBarHidden(true)
                        .ignoresSafeArea()
                } else {
                    portraitContent
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCutsTab)) { _ in
                cutsVM.reload()
                showStartSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMealPlanEditor)) { _ in
                cutsVM.reload()
                showMealPlanEditor = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCoachForMealSetup)) { _ in
                autoRecordConversations = false
                showConversations = true
            }
            .onAppear {
                cutsVM.reload()
                if !didLoad {
                    viewModel.loadForDate(Date(), repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit, cycleStarts: services.cycleStarts, milestoneStore: services.milestoneStore)
                    weightInputActive = false
                    didLoad = true
                    // Cold launch always opens on the same lens — Current Weight
                    // when enabled, otherwise the first enabled one. The choice
                    // is retained for the session but never persisted.
                    lensSelection = TodayLensOrder.launchLens(in: enabledLenses)
                }
                // Settings may have hidden the lens we were showing.
                if !enabledLenses.contains(lensSelection) {
                    lensSelection = TodayLensOrder.launchLens(in: enabledLenses)
                }
                // Allow rotation while the user is on Today; revert on
                // disappear (e.g. tab switch) so other tabs stay
                // portrait-locked.
                AppOrientation.shared.set(.allButUpsideDown)
            }
            .onDisappear {
                AppOrientation.shared.set(.portrait)
            }
            .onChange(of: lensHiddenRaw) { _, _ in
                if !enabledLenses.contains(lensSelection) {
                    lensSelection = TodayLensOrder.launchLens(in: enabledLenses)
                }
            }
            .onChange(of: weightUnitRaw) { _, _ in
                viewModel.loadForDate(viewModel.date, repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit, cycleStarts: services.cycleStarts, milestoneStore: services.milestoneStore)
                weightInputActive = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .milestoneDidChange)) { _ in
                viewModel.milestones = services.milestoneStore.upcoming(from: Date())
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

    @ViewBuilder
    private var landscapeContent: some View {
        if let chartModel = viewModel.chartModel, let domains = viewModel.chartDomains {
            LandscapeFocusChart(
                chartModel: chartModel,
                domains: domains,
                unit: weightUnit
            )
        } else {
            // No active cut yet — fall back to a minimal hint instead of
            // showing the portrait UI sideways.
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                Text("Start a cut to see the focus chart")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var portraitContent: some View {
        ZStack(alignment: .top) {
            // The semantic base for the whole screen — behind the status bar and
            // the custom top bar too. Each lens page draws its own decorative
            // masked layer over this same system background, so the top of the
            // screen is always pure system background (correct in light and dark)
            // and there is never a white seam under the bars.
            Color(.systemBackground)
                .ignoresSafeArea()

            // The Today controls are a custom row that is simply the first
            // content of the canvas, so the gradient genuinely runs behind the
            // status bar. Fighting the system navigation bar's background
            // (toolbarBackground(.hidden)) did not survive on-device; hiding the
            // bar outright removes the white band at the source.
            VStack(spacing: 0) {
                topBar
                todayContent
            }

            // Save confirmation floats above the canvas and auto-dismisses.
            if let saved = viewModel.lastSaved {
                ConfirmationCard(confirmation: saved) {
                    withAnimation { viewModel.lastSaved = nil }
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sensoryFeedback(.success, trigger: viewModel.lastSaved)
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(isPresented: $showConversations) {
                CoachConversationsView(autoRecordNewest: autoRecordConversations)
                    .environmentObject(services)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showStartSheet) {
                if let recent = cutsVM.mostRecentReading {
                    StartCutSheet(startWeightKg: recent.weightKg) { cut in
                        Task { await cutsVM.startCut(cut) }
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let active = cutsVM.activeCut {
                    EditCutSheet(
                        cut: active,
                        onSave: { updated in
                            Task { await cutsVM.updateCut(updated) }
                        },
                        onCancelCut: {
                            Task { await cutsVM.markDone() }
                        }
                    )
                }
            }
            .sheet(isPresented: $showCutHistory) {
                cutHistorySheet
            }
            .navigationDestination(isPresented: $showMealPlanEditor) {
                if let cut = cutsVM.activeCut {
                    MealPlanDetail(cutStartDate: cut.startDate)
                }
            }
            .sheet(isPresented: $showLogSheet) {
                LogWeightSheet(
                    displayValue: Binding(
                        get: { viewModel.displayValue },
                        set: { viewModel.displayValue = $0 }
                    ),
                    unit: weightUnit,
                    date: viewModel.date,
                    hasEntry: viewModel.hasEntry,
                    subtitle: emaSubtitle,
                    onUnitTap: toggleUnit,
                    onSave: {
                        Task { @MainActor in
                            await viewModel.save(services: services, weightUnit: weightUnit, bodyUnit: bodyUnit)
                            weightInputActive = false
                            showLogSheet = false
                        }
                    }
                )
                .presentationDetents([.height(360), .medium])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showDetailChart) {
                if let chartModel = viewModel.chartModel, let domains = viewModel.chartDomains {
                    LensDetailCover(chartModel: chartModel, domains: domains, unit: weightUnit) {
                        showDetailChart = false
                    }
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                        .overlay(Button("Close") { showDetailChart = false })
                }
            }
    }

    // MARK: - Custom top bar
    //
    // Replaces the system navigation bar so the canvas gradient can reach the
    // very top of the screen. It sits inside the safe area (so it clears the
    // status bar) while the gradient behind it does not.

    private var topBar: some View {
        ZStack {
            titleControl
            HStack(spacing: 0) {
                NavigationLink {
                    ProgressTabView(embedded: true)
                        .environmentObject(services)
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .barIcon()
                }
                .accessibilityLabel("Progress")

                Spacer(minLength: 0)

                HStack(spacing: 14) {
                    if !Calendar.current.isDateInToday(viewModel.date) {
                        Button("Today") { selectDate(Date()) }
                            .font(.subheadline.weight(.semibold))
                    }
                    Button { startVoiceCheckIn() } label: {
                        Image(systemName: "mic").barIcon()
                    }
                    .accessibilityLabel("Talk to coach")

                    cutMenu

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").barIcon()
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .tint(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Two-line date control: the cut day number above the relative-day label.
    /// The full date lives under the hero, so it is never repeated here.
    private var titleControl: some View {
        Button {
            showDatePicker = true
        } label: {
            VStack(spacing: 0) {
                if cutDayNumber != nil {
                    Text(titleText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 3) {
                    Text(subtitleText)
                        .font(cutDayNumber == nil ? .headline : .caption)
                        .foregroundStyle(cutDayNumber == nil ? Color.primary : Color.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selected date \(subtitleText)\(cutDayNumber.map { ", day \($0) of the cut" } ?? ""). Tap to pick a date.")
    }

    @ViewBuilder
    private var todayContent: some View {
        ZStack(alignment: .top) {
            if let active = viewModel.activeCut,
               let chartModel = viewModel.chartModel,
               let domains = viewModel.chartDomains,
               let weekly = viewModel.weeklyChartModel,
               let pace = viewModel.paceModel,
               let thisWeek = viewModel.thisWeekModel,
               let projection = viewModel.projection {
                TodayLensCarousel(
                    active: active,
                    projection: projection,
                    chart: chartModel,
                    domains: domains,
                    weekly: weekly,
                    pace: pace,
                    thisWeek: thisWeek,
                    unit: weightUnit,
                    hasEntryToday: hasReadingToday,
                    dayNumber: todayCutDayNumber,
                    selectedDate: viewModel.date,
                    selectedDayValue: viewModel.displayValue,
                    selectedDayLogged: viewModel.hasEntry,
                    selectedDayNumber: cutDayNumber,
                    lenses: enabledLenses,
                    onToggleUnit: toggleUnit,
                    onLog: { showLogSheet = true },
                    onOpenDetail: { showDetailChart = true },
                    selection: $lensSelection
                )
                .animation(.easeInOut(duration: 0.35), value: viewModel.inCutReadings.count)
            } else {
                noCutContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - No active cut

    @ViewBuilder
    private var noCutContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "flag.checkered")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No active cut")
                .font(.title2.weight(.semibold))
            Text("Start a cut to see your weight, pace, and forecast.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                cutsVM.reload()
                showStartSheet = true
            } label: {
                Text("Start a cut")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(cutsVM.mostRecentReading == nil)
            Button("Log weight") { showLogSheet = true }
                .font(.subheadline)
                .padding(.top, 4)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Whether a reading exists for today specifically (independent of the
    /// browsed date), driving the "Log today" affordance in the hero.
    private var hasReadingToday: Bool {
        viewModel.allReadings.contains { Calendar.current.isDateInToday($0.date) }
    }

    /// Cut day number for *today*, used for the hero clarifier.
    private var todayCutDayNumber: Int? {
        guard let cut = viewModel.activeCut else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: cut.startDate)
        let today = cal.startOfDay(for: Date())
        guard today >= start else { return nil }
        return (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
    }

    // MARK: - Title

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

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

    /// Line 1 of the date control: the cut day indicator, e.g. "Day 85".
    /// Falls back to the relative label when there is no active cut, so the
    /// control is never empty.
    private var titleText: String {
        cutDayNumber.map { "Day \($0)" } ?? subtitleText
    }

    /// Line 2 of the date control: the relative-day label —
    /// "Today"/"Yesterday"/weekday/date. The full date lives under the hero, so
    /// it is never repeated here.
    private var subtitleText: String {
        let cal = Calendar.current
        if cal.isDateInToday(viewModel.date) { return "Today" }
        if cal.isDateInYesterday(viewModel.date) { return "Yesterday" }
        let daysAgo = cal.dateComponents([.day], from: viewModel.date, to: Date()).day ?? 0
        if daysAgo > 0 && daysAgo < 7 {
            return Self.weekdayFormatter.string(from: viewModel.date)
        }
        return Self.mediumDateFormatter.string(from: viewModel.date)
    }

    // MARK: - Date navigation
    //
    // Date navigation lives entirely in the title/date-picker control now. The
    // horizontal swipe belongs to the lens carousel, so there is one
    // unambiguous meaning for a left/right drag across the Today canvas.

    private func selectDate(_ d: Date) {
        let day = Reading.dayStart(of: d)
        guard day != viewModel.date else { return }
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.lastSaved = nil
            weightInputActive = false
            viewModel.loadForDate(day, repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit, cycleStarts: services.cycleStarts, milestoneStore: services.milestoneStore)
        }
    }

    private func toggleUnit() {
        let next: WeightUnit = (weightUnit == .lbs) ? .kg : .lbs
        let kg = UnitConvert.storeWeight(viewModel.displayValue, from: weightUnit)
        viewModel.displayValue = (UnitConvert.displayWeight(kg: kg, in: next) * 10.0).rounded() / 10.0
        weightUnitRaw = next.rawValue
    }

    private func startVoiceCheckIn() {
        autoRecordConversations = true
        showConversations = true
    }

    // MARK: - Cut management menu

    @ViewBuilder
    private var cutMenu: some View {
        Menu {
            if cutsVM.activeCut != nil {
                Button {
                    cutsVM.reload()
                    showEditSheet = true
                } label: {
                    Label("Edit cut", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    Task { await cutsVM.markDone() }
                } label: {
                    Label("End cut", systemImage: "flag.checkered")
                }
            } else {
                Button {
                    cutsVM.reload()
                    showStartSheet = true
                } label: {
                    Label("Start cut", systemImage: "plus")
                }
                .disabled(cutsVM.mostRecentReading == nil)
            }
            Button {
                cutsVM.reload()
                showCutHistory = true
            } label: {
                Label("Cut history", systemImage: "clock")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Cut options")
    }

    private var cutHistorySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if cutsVM.historicalCuts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("No history yet")
                                .font(.headline)
                            Text("Past weight-loss runs appear here automatically once enough history is logged.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        ForEach(cutsVM.historicalCuts) { cut in
                            HistoricalCutCard(
                                cut: cut,
                                unit: weightUnit,
                                readings: cutsVM.allReadings
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Cut History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCutHistory = false }
                }
            }
        }
    }

}


/// Shared sizing/weight for the custom top-bar glyphs so the row reads like a
/// system bar even though it is ordinary canvas content.
private extension Image {
    func barIcon() -> some View {
        self.font(.system(size: 17, weight: .regular))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
    }
}

#Preview {
    TodayView()
        .environmentObject(AppServices.shared)
}
