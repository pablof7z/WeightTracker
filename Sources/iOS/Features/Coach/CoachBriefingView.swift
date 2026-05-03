import SwiftUI

struct CoachBriefingView: View {
    var isTab: Bool = false

    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var recordingStore = VoiceRecordingDraftStore.shared
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel: String = AppConstants.defaultElevenLabsSTTModel
    @AppStorage(AppPrefKey.elevenLabsVoiceID) private var voiceID: String = AppConstants.defaultElevenLabsVoiceID

    @State private var items: [BriefingItem] = []
    @State private var currentIndex: Int = 0
    @State private var lastRunAt: Date?
    @State private var didLoad = false
    @State private var showConversation = false
    @State private var showVoiceNotes = false
    @State private var voiceNotesScrollTo: UUID?
    @State private var failedRecordingID: UUID?

    private var voiceNotesBadgeCount: Int {
        recordingStore.recordings.filter {
            $0.status == .failed || $0.status == .needsTranscription
        }.count
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if items.isEmpty || currentIndex >= items.count {
                    caughtUpView
                        .transition(.opacity)
                } else {
                    cardStack
                }

                // Failure toast
                if let failedID = failedRecordingID {
                    failureToast(failedID: failedID)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: failedRecordingID)
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isTab {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CoachHistoryView().environmentObject(services)
                    } label: {
                        Label("History", systemImage: "clock")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        voiceNotesScrollTo = nil
                        showVoiceNotes = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Label("Voice Notes", systemImage: "waveform")
                            if voiceNotesBadgeCount > 0 {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showVoiceNotes) {
                VoiceNotesView(scrollToID: voiceNotesScrollTo)
            }
            .onAppear {
                if !didLoad { didLoad = true; reload() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .coachProposalDidChange)) { _ in reload() }
            .sheet(isPresented: $showConversation, onDismiss: { reload() }) {
                CoachConversationSheet(
                    agentSession: services.coachAgent,
                    sttModel: sttModel,
                    voiceID: voiceID
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Card stack

    @ViewBuilder
    private var cardStack: some View {
        VStack(spacing: 12) {
            progressIndicator
                .padding(.horizontal, 20)

            ZStack(alignment: .top) {
                // Stacked hints behind the active card
                ForEach(Array(stackedHints.enumerated()), id: \.element.id) { offset, _ in
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.regularMaterial)
                        .frame(minHeight: 220)
                        .padding(.horizontal, CGFloat(20 + (offset + 1) * 8))
                        .padding(.top, CGFloat((offset + 1) * 8))
                        .opacity(0.5 - Double(offset) * 0.2)
                        .allowsHitTesting(false)
                }

                CoachBriefingCard(
                    item: items[currentIndex],
                    onAdvance: advance,
                    onSnooze: advance,
                    onDismissAll: dismissAll,
                    onTalkToCoach: { showConversation = true }
                )
                .environmentObject(services)
                .padding(.horizontal, 16)
                .gesture(swipeGesture)
                .id(items[currentIndex].id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .animation(.easeInOut(duration: 0.25), value: currentIndex)
        }
        .padding(.bottom, 24)
    }

    private var progressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(items.count, 1), id: \.self) { i in
                Capsule()
                    .fill(pillColor(for: i))
                    .frame(width: 20, height: 4)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
            Spacer()
            Text(currentIndex < items.count
                 ? "\(currentIndex + 1) of \(items.count)"
                 : "All clear")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func pillColor(for i: Int) -> Color {
        if i < currentIndex { return .secondary.opacity(0.6) }
        if i == currentIndex { return .accentColor }
        return .secondary.opacity(0.25)
    }

    private var stackedHints: [BriefingItem] {
        Array(items.dropFirst(currentIndex + 1).prefix(2))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.width < -60 { advance() }
            }
    }

    // MARK: - Caught up

    @ViewBuilder
    private var caughtUpView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // All-done indicator
                HStack(spacing: 6) {
                    ForEach(0..<max(items.count, 3), id: \.self) { _ in
                        Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 20, height: 4)
                    }
                    Spacer()
                    Text("All clear")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: 6) {
                        Text("You're caught up")
                            .font(.title2.weight(.bold))
                        Text("No new proposals. Keep doing what you're doing.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    CaughtUpSummary()
                        .environmentObject(services)
                }
                .padding(24)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 16)

                VStack(spacing: 10) {
                    Button { showConversation = true } label: {
                        Label("Talk to coach", systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButtonStyle(prominent: true)

                    NavigationLink {
                        CoachHistoryView().environmentObject(services)
                    } label: {
                        Label("View history", systemImage: "clock")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButtonStyle()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Failure toast

    private func failureToast(failedID: UUID) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't transcribe right now.")
                    .font(.subheadline.weight(.semibold))
                Text("Your voice note is saved — review it in Voice Notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                voiceNotesScrollTo = failedID
                showVoiceNotes = true
                failedRecordingID = nil
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glass(in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .onTapGesture { withAnimation { failedRecordingID = nil } }
    }

    // MARK: - Flow

    private func advance() {
        currentIndex = currentIndex + 1 < items.count ? currentIndex + 1 : items.count
    }

    private func dismissAll() { currentIndex = items.count }

    private func reload() {
        lastRunAt = UserDefaults.standard.object(forKey: "coach.lastRunAt") as? Date
        var loaded: [BriefingItem] = []
        if let cut = ActiveCutStore.load() {
            loaded += services.coachProposalStore.pendingProposals(forCutStartDate: cut.startDate)
                .map { BriefingItem(kind: .proposal($0)) }
        }
        if loaded.isEmpty,
           let note = services.coachAuditStore.recentNotes(limit: 5, userVisibleOnly: true).first {
            loaded.append(BriefingItem(kind: .observation(note)))
        }
        items = loaded
        currentIndex = min(currentIndex, max(0, loaded.count))
    }
}

// MARK: - BriefingItem

struct BriefingItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case proposal(CoachProposal)
        case observation(CoachNote)
    }
    let kind: Kind
    var id: UUID {
        switch kind {
        case .proposal(let p): return p.id
        case .observation(let n): return n.id
        }
    }
    static func == (lhs: BriefingItem, rhs: BriefingItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Card dispatcher

private struct CoachBriefingCard: View {
    @EnvironmentObject private var services: AppServices
    let item: BriefingItem
    let onAdvance: () -> Void
    let onSnooze: () -> Void
    let onDismissAll: () -> Void
    let onTalkToCoach: () -> Void

    var body: some View {
        switch item.kind {
        case .proposal(let p):
            ProposalCard(proposal: p, onApply: onAdvance, onSnooze: onSnooze,
                         onDismissAll: onDismissAll, onTalkToCoach: onTalkToCoach)
                .environmentObject(services)
        case .observation(let n):
            ObservationCard(note: n, onAck: onAdvance, onTalkToCoach: onTalkToCoach)
                .environmentObject(services)
        }
    }
}

// MARK: - Proposal card

private struct ProposalCard: View {
    @EnvironmentObject private var services: AppServices

    let proposal: CoachProposal
    let onApply: () -> Void
    let onSnooze: () -> Void
    let onDismissAll: () -> Void
    let onTalkToCoach: () -> Void

    @State private var changes: [CoachProposalChange] = []
    @State private var acceptedChanges: Set<UUID> = []
    @State private var existingReplies: [CoachUserReply] = []
    @State private var replyText: String = ""
    @State private var replySent: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Type label
                HStack(spacing: 8) {
                    Label(changeTypeLabel, systemImage: changeTypeIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                    Spacer()
                    Text(Self.relative(proposal.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Reasoning
                VStack(alignment: .leading, spacing: 8) {
                    Self.markdownText(proposal.reasoning)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Changes
                if !changes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Proposed changes")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            ForEach(changes, id: \.id) { change in
                                ChangeRow(
                                    change: change,
                                    isAccepted: acceptedChanges.contains(change.id),
                                    onToggle: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            if acceptedChanges.contains(change.id) {
                                                acceptedChanges.remove(change.id)
                                            } else {
                                                acceptedChanges.insert(change.id)
                                            }
                                        }
                                    }
                                )

                                if change.id != changes.last?.id {
                                    Divider().padding(.leading, 48)
                                }
                            }
                        }
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                // Actions
                VStack(spacing: 10) {
                    Button(action: applySelected) {
                        Label(
                            "Accept \(acceptedChanges.count == changes.count ? "all" : "\(acceptedChanges.count) of \(changes.count)")",
                            systemImage: "checkmark"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .glassButtonStyle(prominent: true)
                    .disabled(acceptedChanges.isEmpty)

                    HStack(spacing: 10) {
                        Button(action: onSnooze) {
                            Label("Snooze", systemImage: "clock.badge.xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .glassButtonStyle()

                        Button(action: onDismissAll) {
                            Label("Dismiss", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .glassButtonStyle()
                    }

                    Button(action: onTalkToCoach) {
                        Label("Talk to coach", systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButtonStyle()
                }

                // Reply
                replySection
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
        .onAppear {
            changes = services.coachProposalStore.changes(forProposalId: proposal.id)
            acceptedChanges = Set(changes.map(\.id))
            existingReplies = services.coachProposalStore.replies(forProposalId: proposal.id)
        }
    }

    // MARK: Reply

    @ViewBuilder
    private var replySection: some View {
        Divider()

        if !existingReplies.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your replies")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(existingReplies, id: \.id) { reply in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "person.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reply.body).font(.subheadline)
                            Text(Self.relative(reply.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }

        if replySent {
            Label("Coach will see this in the next run", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                TextField("Reply to coach…", text: $replyText, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...4)
                Button(action: sendReply) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
                .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Helpers

    private var changeTypeLabel: String {
        let types = Set(changes.map(\.changeType))
        if types.contains(.macroPlan) { return "Macros" }
        if types.contains(.mealSchedule) { return "Meal schedule" }
        if types.contains(.stepTarget) { return "Activity" }
        return "Plan update"
    }

    private var changeTypeIcon: String {
        let types = Set(changes.map(\.changeType))
        if types.contains(.macroPlan) { return "fork.knife" }
        if types.contains(.mealSchedule) { return "calendar" }
        if types.contains(.stepTarget) { return "figure.walk" }
        return "brain.head.profile"
    }

    private func sendReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let saved = services.coachProposalStore.recordReply(proposalId: proposal.id, body: trimmed)
        existingReplies.append(saved)
        replyText = ""
        withAnimation { replySent = true }
    }

    private func applySelected() {
        for change in changes {
            if acceptedChanges.contains(change.id) { services.coachProposalStore.acceptChange(change) }
            else { services.coachProposalStore.rejectChange(change) }
        }
        services.coachProposalStore.finalizeProposal(proposal)
        NotificationCenter.default.post(name: .coachProposalDidChange, object: nil)
        onApply()
    }

    static func markdownText(_ raw: String) -> Text {
        if let attr = try? AttributedString(markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(raw)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
    private static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Change row

private struct ChangeRow: View {
    let change: CoachProposalChange
    let isAccepted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                Image(systemName: isAccepted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isAccepted ? Color.accentColor : Color.secondary)
                    .animation(.easeInOut(duration: 0.15), value: isAccepted)

                VStack(alignment: .leading, spacing: 3) {
                    Text(change.label)
                        .font(.subheadline)
                        .foregroundStyle(isAccepted ? .primary : .secondary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Text(displayValue(change.beforeJSON))
                            .foregroundStyle(.secondary)
                            .strikethrough(!isAccepted)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(displayValue(change.afterJSON))
                            .fontWeight(.semibold)
                            .foregroundStyle(isAccepted ? .primary : .secondary)
                    }
                    .font(.caption)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func displayValue(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return json }
        if let dict = obj as? [String: Any] {
            for key in ["calories", "kcal", "protein", "carbs", "fat", "steps", "value"] {
                if let v = dict[key] {
                    if let n = v as? Double { return n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n) }
                    if let n = v as? Int { return "\(n)" }
                    if let s = v as? String { return s }
                }
            }
            if let first = dict.values.first {
                if let n = first as? Double { return n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n) }
                if let s = first as? String { return s }
            }
        }
        if let n = obj as? Double { return n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n) }
        return json
    }
}

// MARK: - Observation card

private struct ObservationCard: View {
    @EnvironmentObject private var services: AppServices

    let note: CoachNote
    let onAck: () -> Void
    let onTalkToCoach: () -> Void

    @State private var replyText: String = ""
    @State private var replySent: Bool = false
    @State private var sentReplies: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Type label
                Label("Observation", systemImage: "eye")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                // Note text
                Self.markdownText(note.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // No-change callout
                Label("No changes — I'll keep watching and propose adjustments if needed.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                // Actions
                VStack(spacing: 10) {
                    Button(action: onAck) {
                        Label("Got it", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButtonStyle(prominent: true)

                    Button(action: onTalkToCoach) {
                        Label("Talk to coach", systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButtonStyle()
                }

                // Reply
                Divider()

                if !sentReplies.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sentReplies, id: \.self) { body in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "person.circle.fill")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(body).font(.subheadline)
                            }
                        }
                    }
                }

                if replySent {
                    Label("Coach will see this in the next run", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        TextField("Reply to coach…", text: $replyText, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(1...4)
                        Button(action: sendReply) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title3)
                                .foregroundStyle(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                                                 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                        }
                        .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private static func markdownText(_ raw: String) -> Text {
        if let attr = try? AttributedString(markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(raw)
    }

    private func sendReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        services.coachProposalStore.recordReply(proposalId: nil, body: trimmed)
        sentReplies.append(trimmed)
        replyText = ""
        withAnimation { replySent = true }
    }
}

// MARK: - Changes list (for CoachProposalSheet)

struct CoachProposalChangesView: View {
    let changes: [CoachProposalChange]
    @Binding var acceptedChanges: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if changes.isEmpty {
                Text("No specific changes attached to this proposal.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(changes, id: \.id) { change in
                    HStack {
                        Toggle(isOn: bindingFor(change.id)) {
                            Text(change.label).font(.subheadline).multilineTextAlignment(.leading)
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func bindingFor(_ id: UUID) -> Binding<Bool> {
        Binding(get: { acceptedChanges.contains(id) },
                set: { if $0 { acceptedChanges.insert(id) } else { acceptedChanges.remove(id) } })
    }
}

// MARK: - Caught up summary

struct CaughtUpSummary: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.label) { row in
                HStack {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(row.valueColor)
                }
                .padding(.vertical, 8)

                if row.label != rows.last?.label {
                    Divider()
                }
            }
        }
    }

    private struct Row { let label: String; let value: String; let valueColor: Color }

    private var rows: [Row] {
        [
            Row(label: "Avg weekly loss", value: avgLossLabel, valueColor: .green),
            Row(label: "Macro adherence", value: adherenceLabel, valueColor: .green),
            Row(label: "Days remaining", value: daysLeftLabel, valueColor: .primary),
        ]
    }

    private var avgLossLabel: String {
        guard let cut = ActiveCutStore.load() else { return "—" }
        let lbPerDay = UnitConvert.kgToLb((cut.startWeightKg - cut.targetWeightKg) / Double(max(1, cut.totalDays)))
        return String(format: "−%.2f lb/wk", abs(lbPerDay) * 7)
    }
    private var adherenceLabel: String {
        guard let cut = ActiveCutStore.load() else { return "—" }
        let misses = services.macroDeviationStore.deviationsInLastDays(7, cutStartDate: cut.startDate).count
        return "\(Int((Double(max(0, 7 - misses)) / 7.0 * 100).rounded()))%"
    }
    private var daysLeftLabel: String {
        guard let cut = ActiveCutStore.load() else { return "—" }
        return "\(cut.daysRemaining())"
    }
}
