import SwiftUI

// MARK: - Conversations list (root of the unified coach experience)

/// Telegram-style list of coach conversations. Replaces the old Coach tab,
/// `TodayCoachSheet`, `VoiceCheckInSheet` and the fragmented voice-notes screen.
///
/// - Legacy notes and all automated coach output live in the default "Coach"
///   conversation (see `CoachConversationGrouping`).
/// - Tapping a row opens its thread. "New conversation" starts a fresh thread.
/// - When presented from the Today mic, `autoRecordNewest` resumes the newest
///   conversation and starts recording immediately (tap-and-talk).
struct CoachConversationsView: View {
    var autoRecordNewest: Bool = false

    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var summaries: [CoachConversationSummary] = []
    @State private var path: [UUID] = []
    @State private var autoRecordID: UUID?
    @State private var didOpenInitial = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(summaries) { summary in
                    Button {
                        path.append(summary.id)
                    } label: {
                        ConversationRow(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startNewConversation()
                    } label: {
                        Label("New conversation", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                CoachThreadView(conversationID: id, autoRecord: id == autoRecordID)
                    .environmentObject(services)
                    .onAppear { autoRecordID = nil }
            }
            .onAppear {
                reload()
                openInitialIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .coachProposalDidChange)) { _ in
                reload()
            }
        }
    }

    private func startNewConversation() {
        let id = UUID()
        autoRecordID = nil
        path.append(id)
    }

    private func openInitialIfNeeded() {
        guard autoRecordNewest, !didOpenInitial, path.isEmpty else { return }
        didOpenInitial = true
        let newest = summaries.first?.id ?? CoachConversationGrouping.defaultConversationID
        autoRecordID = newest
        path = [newest]
    }

    private func reload() {
        let notes = services.coachAuditStore.recentNotes(limit: 400, userVisibleOnly: true)
        summaries = CoachConversationGrouping.conversations(from: notes)
    }
}

// MARK: - Conversation row

private struct ConversationRow: View {
    let summary: CoachConversationSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(summary.isDefault ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: summary.isDefault ? "brain.head.profile" : "bubble.left.and.bubble.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(summary.isDefault ? Color.accentColor : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if let activity = summary.lastActivity {
                        Text(activity, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(summary.lastMessagePreview.isEmpty ? "No messages yet" : summary.lastMessagePreview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Thread view (single conversation)

struct CoachThreadView: View {
    let conversationID: UUID
    var autoRecord: Bool = false

    @EnvironmentObject private var services: AppServices
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel: String = AppConstants.defaultElevenLabsSTTModel

    @StateObject private var controller: CoachConversationController
    @StateObject private var playback = RecordingsPlaybackController()

    @State private var items: [ThreadItem] = []
    @State private var didLoad = false
    @State private var didAutoRecord = false
    @State private var scrollTick = 0

    init(conversationID: UUID, autoRecord: Bool = false) {
        self.conversationID = conversationID
        self.autoRecord = autoRecord
        let services = AppServices.shared
        _controller = StateObject(wrappedValue: CoachConversationController(
            agentSession: services.coachAgent,
            sttModel: AppConstants.defaultElevenLabsSTTModel,
            auditStore: services.coachAuditStore,
            autoResetAfterReply: true
        ))
    }

    private var isDefault: Bool { conversationID == CoachConversationGrouping.defaultConversationID }

    var body: some View {
        VStack(spacing: 0) {
            threadScroll
            Divider()
            inputBar
        }
        .navigationTitle(isDefault ? "Coach" : "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            controller.conversationID = isDefault ? nil : conversationID
            if !didLoad { didLoad = true; reload() }
            if autoRecord, !didAutoRecord {
                didAutoRecord = true
                Task { await controller.startRecording() }
            }
        }
        .onDisappear {
            controller.teardown()
            playback.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .coachProposalDidChange)) { _ in
            reload()
            scrollTick += 1
        }
    }

    // MARK: Thread scroll

    private var threadScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in
                            cell(for: item)
                        }
                    }
                    if case .thinking = controller.state {
                        thinkingBubble
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: items.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: scrollTick) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: controller.state) { _, state in
                if case .thinking = state {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for item: ThreadItem) -> some View {
        switch item {
        case .note(let note):
            if note.audioDraftID != nil {
                AudioMessageBubble(note: note, playback: playback)
            } else {
                NoteBubble(note: note)
            }
        case .proposal(let proposal):
            ProposalThreadCard(proposal: proposal, onUpdate: reload)
                .environmentObject(services)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 60)
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(isDefault ? "Talk to your coach" : "New conversation")
                .font(.headline)
            Text("Tap the mic to talk, or type a message.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var thinkingBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            micButton
            TextField("Message coach…", text: $controller.inputText, axis: .vertical)
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
        .disabled(controller.state == .thinking)
        .opacity(controller.state == .thinking ? 0.5 : 1)
    }

    private var micButton: some View {
        Button {
            Task { await handleMicTap() }
        } label: {
            Image(systemName: micIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(controller.stt.isRecording ? Color.accentColor : Color.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(controller.stt.isRecording
                        ? Color.accentColor.opacity(0.15)
                        : Color(.secondarySystemGroupedBackground))
                )
                .animation(.easeInOut(duration: 0.1), value: controller.stt.isRecording)
        }
        .accessibilityLabel(controller.stt.isRecording ? "Stop recording" : "Start recording")
    }

    private var micIcon: String {
        if controller.stt.isStarting { return "ellipsis" }
        if controller.stt.isRecording { return "stop.fill" }
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
        guard controller.state != .thinking else { return false }
        let hasText = !controller.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || controller.stt.isRecording
    }

    private func sendIfReady() {
        guard canSend else { return }
        Task {
            await controller.sendTurn()
            reload()
        }
    }

    private func handleMicTap() async {
        if controller.stt.isRecording || controller.stt.isStarting {
            await controller.stopRecording()
        } else {
            await controller.startRecording()
        }
    }

    // MARK: Data

    private func reload() {
        let notes = services.coachAuditStore.recentNotes(limit: 400, userVisibleOnly: true)
        let messages = CoachConversationGrouping.messages(in: conversationID, from: notes)
        var result: [ThreadItem] = messages.map { ThreadItem.note($0) }
        if isDefault, let cut = ActiveCutStore.load() {
            let proposals = services.coachProposalStore.allProposals(forCutStartDate: cut.startDate)
            result += proposals.map { ThreadItem.proposal($0) }
        }
        items = result.sorted { $0.createdAt < $1.createdAt }
    }
}

// MARK: - Audio message bubble

/// Renders a voice message as an audio bubble with a play control. If a
/// transcript exists it can be expanded; pure audio-only messages (failed
/// transcription) show just the player.
struct AudioMessageBubble: View {
    let note: CoachNote
    @ObservedObject var playback: RecordingsPlaybackController

    @State private var expanded = false

    private var draft: VoiceRecordingDraft? {
        guard let id = note.audioDraftID else { return nil }
        return VoiceRecordingDraftStore.shared.recording(id: id)
    }

    private var isThisPlaying: Bool { draft.map { playback.playingID == $0.id } ?? false }
    private var isPlaying: Bool { isThisPlaying && playback.isPlaying }

    var body: some View {
        HStack {
            Spacer(minLength: 50)
            VStack(alignment: .trailing, spacing: 6) {
                if let draft {
                    playerRow(draft: draft)
                    if expanded, let t = note.text.nilIfBlank {
                        Text(t)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                } else {
                    // Audio no longer on device — fall back to any transcript.
                    Text(note.text.nilIfBlank ?? "Voice message (audio unavailable)")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }
                Text(note.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func playerRow(draft: VoiceRecordingDraft) -> some View {
        HStack(spacing: 10) {
            Button {
                playback.togglePlayPause(recording: draft)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)

            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            Text(formatTime(isThisPlaying ? playback.progress : draft.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))

            if note.text.nilIfBlank != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
