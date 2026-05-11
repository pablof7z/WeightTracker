import SwiftUI

// MARK: - Thread item model

enum ThreadItem: Identifiable {
    case note(CoachNote)
    case proposal(CoachProposal)

    var id: UUID {
        switch self {
        case .note(let n): return n.id
        case .proposal(let p): return p.id
        }
    }

    var createdAt: Date {
        switch self {
        case .note(let n): return n.createdAt
        case .proposal(let p): return p.createdAt
        }
    }
}

// MARK: - Coach Thread View (replaces card-stack Briefing)

struct CoachBriefingView: View {
    var isTab: Bool = false

    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var recordingStore = VoiceRecordingDraftStore.shared
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel: String = AppConstants.defaultElevenLabsSTTModel

    @StateObject private var inputController: CoachConversationController
    @State private var items: [ThreadItem] = []
    @State private var didLoad = false
    @State private var showVoiceNotes = false
    @State private var voiceNotesScrollTo: UUID?
    @State private var showHistory = false
    @State private var scrollTarget: String?

    private var voiceNotesBadgeCount: Int {
        recordingStore.recordings.filter {
            $0.status == .failed || $0.status == .needsTranscription
        }.count
    }

    init(isTab: Bool = false) {
        self.isTab = isTab
        let services = AppServices.shared
        _inputController = StateObject(wrappedValue: CoachConversationController(
            agentSession: services.coachAgent,
            sttModel: AppConstants.defaultElevenLabsSTTModel,
            auditStore: services.coachAuditStore,
            autoResetAfterReply: true
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                threadScroll
                Divider()
                inputBar
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .coachProposalDidChange)) { _ in
                reload()
                // Scroll to bottom after new message
                scrollToBottom()
            }
        }
    }

    // MARK: - Thread scroll

    private var threadScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in
                            threadCell(for: item, proxy: proxy)
                        }
                    }

                    // Thinking indicator
                    if case .thinking = inputController.state {
                        thinkingBubble
                    }

                    // Anchor for auto-scroll
                    Color.clear.frame(height: 1).id(scrollAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollTarget) { _, target in
                guard target != nil else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(scrollAnchor, anchor: .bottom)
                }
                scrollTarget = nil
            }
            .onChange(of: inputController.state) { _, state in
                if case .thinking = state {
                    withAnimation { proxy.scrollTo(scrollAnchor, anchor: .bottom) }
                }
            }
        }
    }

    private let scrollAnchor = "thread_bottom"

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Coach is ready")
                    .font(.headline)
                Text("Ask a question, log context, or request a plan update.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func threadCell(for item: ThreadItem, proxy: ScrollViewProxy) -> some View {
        switch item {
        case .note(let note):
            NoteBubble(note: note)
        case .proposal(let proposal):
            ProposalThreadCard(proposal: proposal, onUpdate: reload)
                .environmentObject(services)
        }
    }

    private var thinkingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            micButton
            TextField("Message coach…", text: $inputController.inputText, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .submitLabel(.send)
                .onSubmit { sendIfReady() }

            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .disabled(inputController.state == .thinking)
        .opacity(inputController.state == .thinking ? 0.5 : 1)
    }

    private var micButton: some View {
        Button {
            Task { await handleMicTap() }
        } label: {
            Image(systemName: micIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(inputController.stt.isRecording ? Color.accentColor : Color.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(inputController.stt.isRecording
                        ? Color.accentColor.opacity(0.15)
                        : Color(.secondarySystemGroupedBackground))
                )
                .animation(.easeInOut(duration: 0.1), value: inputController.stt.isRecording)
        }
        .accessibilityLabel(inputController.stt.isRecording ? "Stop recording" : "Start recording")
    }

    private var micIcon: String {
        if inputController.stt.isStarting { return "ellipsis" }
        if inputController.stt.isRecording { return "stop.fill" }
        return "mic.fill"
    }

    private var sendButton: some View {
        Button { sendIfReady() } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
        }
        .disabled(!canSend)
        .accessibilityLabel("Send message")
    }

    private var canSend: Bool {
        guard inputController.state != .thinking else { return false }
        let hasText = !inputController.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || inputController.stt.isRecording
    }

    private func sendIfReady() {
        guard canSend else { return }
        Task { await inputController.sendTurn() }
    }

    private func handleMicTap() async {
        if inputController.stt.isRecording || inputController.stt.isStarting {
            await inputController.stopRecording()
        } else {
            await inputController.startRecording()
        }
    }

    // MARK: - Data loading

    private func reload() {
        var result: [ThreadItem] = []

        let notes = services.coachAuditStore.recentNotes(limit: 150, userVisibleOnly: true)
        result += notes.map { ThreadItem.note($0) }

        if let cut = ActiveCutStore.load() {
            let proposals = services.coachProposalStore.allProposals(forCutStartDate: cut.startDate)
            result += proposals.map { ThreadItem.proposal($0) }
        }

        items = result.sorted { $0.createdAt < $1.createdAt }
    }

    private func scrollToBottom() {
        scrollTarget = "bottom"
    }
}

// MARK: - Note bubble

struct NoteBubble: View {
    let note: CoachNote

    var body: some View {
        if note.source == .user {
            userBubble
        } else {
            coachBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 3) {
                Text(note.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Text(note.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var coachBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                markdownText(note.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(note.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 40)
        }
    }

    private func markdownText(_ raw: String) -> Text {
        if let attr = try? AttributedString(markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(raw)
    }
}

// MARK: - Proposal thread card

struct ProposalThreadCard: View {
    @EnvironmentObject private var services: AppServices
    let proposal: CoachProposal
    let onUpdate: () -> Void

    @State private var changes: [CoachProposalChange] = []
    @State private var acceptedChanges: Set<UUID> = []
    @State private var replyText: String = ""
    @State private var replySent: Bool = false
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded { expandedContent }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            changes = services.coachProposalStore.changes(forProposalId: proposal.id)
            acceptedChanges = Set(changes.map(\.id))
            expanded = proposal.status == .pending
        }
    }

    private var header: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
            HStack(spacing: 10) {
                Image(systemName: proposal.status == .pending ? "pencil.line" : "checkmark.circle.fill")
                    .foregroundStyle(proposal.status == .pending ? Color.accentColor : Color.secondary)
                Text(proposal.status == .pending ? "Plan update proposed" : "Proposal \(proposal.status.rawValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(proposal.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandedContent: some View {
        Divider().padding(.horizontal, 14)

        VStack(alignment: .leading, spacing: 14) {
            ProposalCard.markdownText(proposal.reasoning)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if !changes.isEmpty {
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
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }

            if proposal.status == .pending {
                Button(action: applySelected) {
                    Label(
                        "Accept \(acceptedChanges.count == changes.count ? "all" : "\(acceptedChanges.count) of \(changes.count)")",
                        systemImage: "checkmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: true)
                .disabled(acceptedChanges.isEmpty)

                replySection
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var replySection: some View {
        if replySent {
            Label("Coach will see this in the next run", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                TextField("Reply to coach…", text: $replyText, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...3)
                Button(action: sendReply) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(replyText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
                .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func applySelected() {
        for change in changes {
            if acceptedChanges.contains(change.id) { services.coachProposalStore.acceptChange(change) }
            else { services.coachProposalStore.rejectChange(change) }
        }
        services.coachProposalStore.finalizeProposal(proposal)
        NotificationCenter.default.post(name: .coachProposalDidChange, object: nil)
        onUpdate()
    }

    private func sendReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        services.coachProposalStore.recordReply(proposalId: proposal.id, body: trimmed)
        replyText = ""
        withAnimation { replySent = true }
    }
}

// MARK: - Proposal card (kept for CoachConversationSheet reuse)

struct ProposalCard {
    static func markdownText(_ raw: String) -> Text {
        if let attr = try? AttributedString(markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(raw)
    }
}

// MARK: - Change row (shared)

struct ChangeRow: View {
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
        }
        if let n = obj as? Double { return n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n) }
        return json
    }
}

// MARK: - Caught up summary (kept for backward compat)

struct CaughtUpSummary: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.label) { row in
                HStack {
                    Text(row.label).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.value).font(.subheadline.weight(.semibold)).foregroundStyle(row.valueColor)
                }
                .padding(.vertical, 8)
                if row.label != rows.last?.label { Divider() }
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

// MARK: - CoachProposalChangesView (kept for CoachProposalSheet)

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
