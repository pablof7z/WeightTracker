import SwiftUI
import SwiftData

struct TodayView: View {
    @EnvironmentObject var services: AppServices
    @StateObject private var viewModel = TodayViewModel()
    @StateObject private var stt = ElevenLabsRealtimeSTT()

    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel: String = AppConstants.defaultElevenLabsSTTModel

    @State private var didLoad = false
    @State private var showDatePicker = false
    @State private var showVoiceCheckIn = false
    @State private var todayCoachNote: CoachNote?
    @State private var swipeAccum: CGFloat = 0
    @State private var dismissTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var weightInputActive = false

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }
    private var bodyUnit: BodyUnit { BodyUnit(rawValue: bodyUnitRaw) ?? .inches }
    private var showWeightControls: Bool { !viewModel.hasEntry || weightInputActive }

    private var canGoForward: Bool {
        Calendar.current.startOfDay(for: viewModel.date) < Calendar.current.startOfDay(for: Date())
    }
    private var canGoBack: Bool {
        viewModel.date > viewModel.minDate
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    NumericPad(
                        value: Binding(
                            get: { viewModel.displayValue },
                            set: { newValue in
                                if viewModel.hasEntry {
                                    weightInputActive = true
                                }
                                viewModel.displayValue = newValue
                                viewModel.bumpEditTick()
                            }
                        ),
                        unitSymbol: weightUnit.symbol,
                        controlsVisible: showWeightControls,
                        onValueTap: viewModel.hasEntry ? { revealWeightControls() } : nil,
                        onUnitTap: toggleUnit
                    )
                    .animation(.easeInOut(duration: 0.18), value: showWeightControls)
                    .opacity(viewModel.hasEntry ? 1.0 : 0.45)
                    .padding(.top, 16)

                    if let saved = viewModel.lastSaved {
                        ConfirmationCard(confirmation: saved) {
                            withAnimation { viewModel.lastSaved = nil }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 16)

                if let active = viewModel.activeCut, let projection = viewModel.projection {
                    if let todayCoachNote {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Today note")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(todayCoachNote.text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .glass(in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }

                    cutProgressStrip(active: active, projection: projection)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    ActiveCutMinichart(
                        active: active,
                        inCutReadings: viewModel.inCutReadings,
                        projection: projection,
                        unit: weightUnit
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .gesture(swipeGesture)
            .sensoryFeedback(.success, trigger: viewModel.lastSaved)
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
                    .accessibilityLabel("Previous day")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if canGoForward { goForward() }
                    } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward)
                    .accessibilityLabel("Next day")
                }
                if !Calendar.current.isDateInToday(viewModel.date) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Today") { selectDate(Date()) }
                    }
                }
                if viewModel.activeCut != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { startVoiceCheckIn() } label: {
                            Image(systemName: "mic")
                        }
                    }
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
            .sheet(isPresented: $showVoiceCheckIn, onDismiss: {
                if stt.isRecording || stt.isStarting {
                    stt.cancel()
                }
            }) {
                VoiceCheckInSheet(
                    stt: stt,
                    onFinish: finishVoiceCheckIn,
                    onPause: { stt.pause() },
                    onResume: { stt.resume() }
                )
                .presentationDetents([.height(320), .medium])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                if !didLoad {
                    viewModel.loadForDate(Date(), repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit)
                    weightInputActive = false
                    reloadTodayCoachNote()
                    didLoad = true
                }
            }
            .onChange(of: weightUnitRaw) { _, _ in
                viewModel.loadForDate(viewModel.date, repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit)
                weightInputActive = false
                reloadTodayCoachNote()
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
            .onChange(of: viewModel.editTick) { _, _ in
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    await viewModel.save(services: services, weightUnit: weightUnit, bodyUnit: bodyUnit)
                }
            }
        }
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

    private var titleText: String {
        if let dayNum = cutDayNumber {
            return "Day \(dayNum)"
        }
        let cal = Calendar.current
        if cal.isDateInToday(viewModel.date) { return "Today" }
        if cal.isDateInYesterday(viewModel.date) { return "Yesterday" }
        let daysAgo = cal.dateComponents([.day], from: viewModel.date, to: Date()).day ?? 0
        if daysAgo > 0 && daysAgo < 7 {
            return Self.weekdayFormatter.string(from: viewModel.date)
        }
        return Self.mediumDateFormatter.string(from: viewModel.date)
    }

    private var subtitleText: String {
        if cutDayNumber != nil {
            return Self.mediumDateFormatter.string(from: viewModel.date)
        }
        return viewModel.hasEntry ? "Logged" : "No entry"
    }

    // MARK: - Cut progress strip

    private static let microStatsFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    @ViewBuilder
    private func cutProgressStrip(active: ActiveCut, projection: CutProjectionResult) -> some View {
        let totalLoss = active.startWeightKg - active.targetWeightKg
        let currentLoss = active.startWeightKg - projection.anchorKg
        let progress = totalLoss > 0 ? max(0.0, min(1.0, currentLoss / totalLoss)) : 0.0

        let cal = Calendar.current
        let daysLeft = max(0, cal.dateComponents([.day], from: viewModel.date, to: active.targetEndDate).day ?? 0)

        let targetDisplay = UnitConvert.displayWeight(kg: active.targetWeightKg, in: weightUnit)
        let targetStr = String(format: "%.0f %@", targetDisplay, weightUnit.symbol)
        let endStr = Self.microStatsFmt.string(from: active.targetEndDate)

        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("\(targetStr) · \(endStr)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 3)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(4, geo.size.width * progress), height: 3)
                    }
                }
                .frame(height: 4)

                Text(projection.isTargetReached ? "Done" : "\(daysLeft)d left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            if projection.isTargetReached {
                Text("Target reached — maintain")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Date navigation

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) else { return }
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
        let hadPendingSave = saveTask != nil
        saveTask?.cancel()
        saveTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        let load = {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.lastSaved = nil
                weightInputActive = false
                viewModel.loadForDate(day, repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit)
                reloadTodayCoachNote()
            }
        }
        if hadPendingSave {
            // Flush the pending save against the outgoing date BEFORE we mutate state.
            Task { @MainActor in
                await viewModel.save(services: services, weightUnit: weightUnit, bodyUnit: bodyUnit)
                load()
            }
        } else {
            load()
        }
    }

    private func toggleUnit() {
        let next: WeightUnit = (weightUnit == .lbs) ? .kg : .lbs
        let kg = UnitConvert.storeWeight(viewModel.displayValue, from: weightUnit)
        viewModel.displayValue = (UnitConvert.displayWeight(kg: kg, in: next) * 10.0).rounded() / 10.0
        weightUnitRaw = next.rawValue
    }

    private func revealWeightControls() {
        guard viewModel.hasEntry else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            weightInputActive = true
        }
    }

    private func startVoiceCheckIn() {
        showVoiceCheckIn = true
        Task { @MainActor in
            do {
                try await stt.start(modelID: sttModel)
            } catch {
                stt.recordStartFailure(error)
            }
        }
    }

    private func finishVoiceCheckIn() {
        Task { @MainActor in
            let recordingID = stt.currentRecordingID
            let transcript = await stt.stop()
            showVoiceCheckIn = false

            if services.coachAuditStore.appendNote(
                source: .user,
                kind: .checkIn,
                visibility: .userVisible,
                cutStartDate: ActiveCutStore.load()?.startDate,
                day: Date(),
                text: transcript,
                audioDraftID: recordingID
            ) != nil {
                await services.coachAgent.run(transcript: transcript, trigger: .voiceCheckIn)
                reloadTodayCoachNote()
            }
        }
    }

    private func reloadTodayCoachNote() {
        let day = Reading.dayStart(of: viewModel.date)
        todayCoachNote = services.coachAuditStore
            .recentNotes(limit: 20, userVisibleOnly: true)
            .first { note in
                guard let noteDay = note.day else { return false }
                return Reading.dayStart(of: noteDay) == day
            }
    }

}

#Preview {
    TodayView()
        .environmentObject(AppServices.shared)
}
