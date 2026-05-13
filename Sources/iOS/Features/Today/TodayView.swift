import SwiftUI
import SwiftData

struct TodayView: View {
    @EnvironmentObject var services: AppServices
    @StateObject private var viewModel = TodayViewModel()

    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel: String = AppConstants.defaultElevenLabsSTTModel

    /// `.compact` vertical size class on iPhone == landscape. Drives the
    /// portrait/landscape body swap on the Today tab. We allow the actual
    /// rotation to happen by widening `AppOrientation.shared.supportedMask`
    /// in `.onAppear` (and reverting it in `.onDisappear`).
    @Environment(\.verticalSizeClass) private var vSizeClass

    @State private var didLoad = false
    @State private var showDatePicker = false
    @State private var showSettings = false
    @State private var showCoachConversation = false
    @ObservedObject private var pinnedNoteStore = TodayPinnedNoteStore.shared
    @State private var swipeAccum: CGFloat = 0
    @State private var dismissTask: Task<Void, Never>?
    @State private var weightInputActive = false

    private var isLandscape: Bool { vSizeClass == .compact }

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }
    private var bodyUnit: BodyUnit { BodyUnit(rawValue: bodyUnitRaw) ?? .inches }
    private var showWeightControls: Bool { !viewModel.hasEntry || weightInputActive }

    /// Subtitle showing the 7-day EMA in the active display unit, or "—" when not enough history.
    private var emaSubtitle: String {
        guard let kg = viewModel.ema7Kg else { return "7-day avg —" }
        let display = UnitConvert.displayWeight(kg: kg, in: weightUnit)
        return String(format: "7-day avg %.1f %@", display, weightUnit.symbol)
    }

    private var canGoForward: Bool {
        Calendar.current.startOfDay(for: viewModel.date) < Calendar.current.startOfDay(for: Date())
    }
    private var canGoBack: Bool {
        viewModel.date > viewModel.minDate
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
            .onAppear {
                if !didLoad {
                    viewModel.loadForDate(Date(), repository: services.repository, unit: weightUnit, bodyUnit: bodyUnit, cycleStarts: services.cycleStarts, milestoneStore: services.milestoneStore)
                    weightInputActive = false
                    didLoad = true
                }
                // Allow rotation while the user is on Today; revert on
                // disappear (e.g. tab switch) so other tabs stay
                // portrait-locked.
                AppOrientation.shared.set(.allButUpsideDown)
            }
            .onDisappear {
                AppOrientation.shared.set(.portrait)
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
        if let active = viewModel.activeCut, let projection = viewModel.projection {
            LandscapeFocusChart(
                active: active,
                inCutReadings: viewModel.inCutReadings,
                projection: projection,
                unit: weightUnit,
                milestones: viewModel.milestones,
                allReadings: viewModel.allReadings
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
                            }
                        ),
                        unitSymbol: weightUnit.symbol,
                        subtitle: emaSubtitle,
                        controlsVisible: showWeightControls,
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

                    if showWeightControls {
                        Button {
                            Task { @MainActor in
                                await viewModel.save(services: services, weightUnit: weightUnit, bodyUnit: bodyUnit)
                                weightInputActive = false
                            }
                        } label: {
                            Text(viewModel.hasEntry ? "Update" : "Log Weight")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)

                // No Spacer here — the chart claims the dead area below the cut
                // strip with its own `maxHeight: .infinity` and bleeds behind the
                // tab bar via `.ignoresSafeArea(.container, edges: .bottom)`.
                if let active = viewModel.activeCut, let projection = viewModel.projection {
                    if let pinnedNote = pinnedNoteStore.pinnedNote {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Coach")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(pinnedNote.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    pinnedNoteStore.dismiss()
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                            }
                            .accessibilityLabel("Dismiss coach note")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .glass(in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    cutProgressStrip(active: active, projection: projection)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    if let deficit = viewModel.deficit {
                        CutDeficitWidget(result: deficit, cutStartDate: active.startDate)
                            .padding(.bottom, 12)
                    }

                    if viewModel.forecast != nil {
                        WeightForecastWidget(
                            readings: viewModel.allReadings,
                            activeCut: active,
                            weightUnit: weightUnit,
                            milestones: viewModel.milestones
                        )
                        .padding(.bottom, 12)
                    }

                    ActiveCutMinichart(
                        active: active,
                        inCutReadings: viewModel.inCutReadings,
                        projection: projection,
                        unit: weightUnit,
                        milestones: viewModel.milestones,
                        allReadings: viewModel.allReadings
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
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
            .sheet(isPresented: $showCoachConversation) {
                TodayCoachSheet(sttModel: sttModel)
                    .environmentObject(services)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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
                    .overlay(alignment: .topLeading) {
                        // Milestone flags float above the bar without taking
                        // layout space. Empty when no milestones, so this is
                        // a true no-op for the existing visual.
                        milestoneMarkers(active: active, projection: projection, barWidth: geo.size.width)
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

    // MARK: - Milestone markers

    /// One marker per milestone group, positioned along the bar by
    /// `(milestone.date − today) / (cutEnd − today)`. Markers within ~50pt
    /// of each other are merged into a single label with a `+N` badge — the
    /// wider threshold accounts for the text-label width (~40pt for "172 lbs"
    /// versus the original 14pt flag).
    @ViewBuilder
    private func milestoneMarkers(active: ActiveCut, projection: CutProjectionResult, barWidth: CGFloat) -> some View {
        if !viewModel.milestones.isEmpty, barWidth > 0 {
            let groups = makeMilestoneGroups(active: active, barWidth: barWidth)
            ZStack(alignment: .topLeading) {
                ForEach(groups) { group in
                    MilestoneMarker(
                        group: group,
                        active: active,
                        readings: viewModel.allReadings,
                        weightUnit: weightUnit
                    )
                    // Center the label on its anchor x and lift it above the
                    // 3pt bar. Estimated label half-width is ~22pt for
                    // "172 lbs" — close enough to center the popover anchor.
                    .offset(x: group.x - 22, y: -22)
                }
            }
            .frame(width: barWidth, height: 1, alignment: .topLeading)
            .allowsHitTesting(true)
        }
    }

    /// Cluster upcoming milestones into bar groups. Computes projected weight
    /// at the anchor (nearest) milestone date so the marker can render a
    /// weight number inline; groups whose projection is unavailable still
    /// appear in the result (the marker renders nothing — bar markers only
    /// motivate when the number is shown).
    private func makeMilestoneGroups(active: ActiveCut, barWidth: CGFloat) -> [MilestoneGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cutEnd = cal.startOfDay(for: active.targetEndDate)
        let totalDays = max(1, cal.dateComponents([.day], from: today, to: cutEnd).day ?? 1)

        // Map each upcoming milestone to a clamped x.
        let positioned: [(milestone: Milestone, x: CGFloat)] = viewModel.milestones
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
            .map { m in
                let days = cal.dateComponents([.day], from: today, to: m.date).day ?? 0
                let raw = CGFloat(days) / CGFloat(totalDays)
                let clamped = min(max(raw, 0), 1)
                return (m, clamped * barWidth)
            }

        // Cluster adjacent markers within ~50pt of each other — sized for
        // the text label width (~40pt) plus a small gap.
        let threshold: CGFloat = 50
        var groups: [MilestoneGroup] = []
        for entry in positioned {
            if var last = groups.last, abs(entry.x - last.x) <= threshold {
                last.milestones.append(entry.milestone)
                // Recompute group x as average of members so it doesn't drift.
                last.x = (last.x + entry.x) / 2
                groups[groups.count - 1] = last
            } else {
                groups.append(MilestoneGroup(milestones: [entry.milestone], x: entry.x, projectedKg: nil))
            }
        }

        // Resolve the projected kg for each group's anchor (nearest) milestone.
        return groups.map { group in
            var g = group
            let anchor = g.milestones.min(by: { $0.date < $1.date }) ?? g.milestones[0]
            let days = max(1, cal.dateComponents([.day], from: today, to: anchor.date).day ?? 1)
            if let result = CutWeightProjector.project(
                activeCut: active,
                readings: viewModel.allReadings,
                horizonDays: days,
                asOf: Date()
            ), !result.isFlat {
                g.projectedKg = result.projectedKg
            }
            return g
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
        showCoachConversation = true
    }

}

// MARK: - Milestone markers (data + view)

/// One or more milestones rendered as a single label on the cut progress bar.
/// `x` is the marker's horizontal pixel offset along the bar. `projectedKg`
/// is the forecast at the nearest (anchor) milestone's date — `nil` means we
/// skip rendering: a bar marker only motivates when we can show a number.
struct MilestoneGroup: Identifiable {
    var milestones: [Milestone]
    var x: CGFloat
    var projectedKg: Double?
    var id: String {
        milestones.map(\.id.uuidString).sorted().joined(separator: "|")
    }
}

/// Inline text label above the cut-progress bar showing the projected weight
/// at the milestone date. Tap → callout with the full name + date for every
/// milestone in the group. Motivational framing: the user sees the goal
/// weight they'll likely hit by their trip / wedding / shoot.
///
/// On iPhone portrait the callout slides up as a sheet; on iPad / landscape
/// SwiftUI's `.popover` adapts automatically. A `+N` badge marks groups with
/// multiple milestones (when two events land within ~50pt of each other).
private struct MilestoneMarker: View {
    let group: MilestoneGroup
    let active: ActiveCut
    let readings: [Reading]
    let weightUnit: WeightUnit

    @State private var showCallout = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let shortDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Anchor milestone for the headline label (nearest in the group).
    private var anchor: Milestone { group.milestones.sorted(by: { $0.date < $1.date }).first ?? group.milestones[0] }

    /// Headline text, e.g. "172 lbs". Whole pounds keep the label tight on
    /// the bar; full precision lives in the callout.
    private var headline: String? {
        guard let kg = group.projectedKg else { return nil }
        let raw = UnitConvert.displayWeight(kg: kg, in: weightUnit)
        return String(format: "%.0f %@", raw.rounded(), weightUnit.symbol)
    }

    var body: some View {
        if let headline {
            Button {
                showCallout = true
            } label: {
                HStack(spacing: 3) {
                    Text(headline)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    if group.milestones.count > 1 {
                        Text("+\(group.milestones.count - 1)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.5), lineWidth: 0.5))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            // `.popover` adapts automatically: popover on iPad/landscape
            // (regular size class) and sheet on iPhone portrait (compact).
            .popover(isPresented: $showCallout, attachmentAnchor: .point(.center), arrowEdge: .top) {
                calloutBody
                    .padding(16)
                    .frame(maxWidth: 280)
            }
        }
    }

    private var accessibilityLabel: String {
        let names = group.milestones.map(\.name).joined(separator: ", ")
        let kgStr = headline ?? ""
        return "Projected \(kgStr) at milestone \(names). Tap for details."
    }

    @ViewBuilder
    private var calloutBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(group.milestones, id: \.id) { m in
                milestoneRow(for: m)
                if m.id != group.milestones.last?.id {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func milestoneRow(for m: Milestone) -> some View {
        // Format: "≈ 172.1 lbs on Aug 21 (Trip)". Falls back to just the
        // date and name when the projection can't compute (cut too young,
        // band too wide, etc.).
        let dateStr = Self.dateFmt.string(from: m.date)
        if let projectionStr = projectedWeight(on: m.date) {
            Text("\(projectionStr) on \(dateStr) (\(m.name))")
                .font(.subheadline)
        } else {
            Text("\(dateStr) (\(m.name))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Returns just the weight + unit portion, e.g. "≈ 172.1 lbs". Caller
    /// concatenates with the date and milestone name.
    private func projectedWeight(on date: Date) -> String? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: date)
        let days = max(1, cal.dateComponents([.day], from: today, to: day).day ?? 1)
        guard let result = CutWeightProjector.project(
            activeCut: active,
            readings: readings,
            horizonDays: days,
            asOf: Date()
        ) else {
            return nil
        }
        if result.isFlat {
            return "no change projected"
        }
        let raw = UnitConvert.displayWeight(kg: result.projectedKg, in: weightUnit)
        let rounded = (raw * 10.0).rounded() / 10.0
        return String(format: "\u{2248} %.1f %@", rounded, weightUnit.symbol)
    }
}

#Preview {
    TodayView()
        .environmentObject(AppServices.shared)
}
