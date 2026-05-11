import SwiftUI
import VoiceCaptureKit

/// Voice-first coach sheet opened from the Today tab mic button.
/// Opens straight into recording; after the agent replies the user can
/// tap the mic button again for a multi-turn conversation.
struct TodayCoachSheet: View {
    let sttModel: String

    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @StateObject private var stt = ElevenLabsRealtimeSTT()
    @State private var conversationMessages: [[String: Any]] = []
    @State private var hasStartedConversation = false
    @State private var phase: Phase = .recording
    @State private var threadItems: [ThreadItem] = []
    @State private var sessionStartDate = Date()

    enum Phase: Equatable {
        case recording, thinking, idle
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    threadScroll
                    if phase != .recording {
                        Divider()
                        bottomBar
                    }
                }
                .navigationTitle("Coach")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }

                if phase == .recording {
                    VoiceCaptureSheet(
                        state: VoiceCaptureSheetState(
                            isStarting: stt.isStarting,
                            isPaused: stt.isPaused,
                            level: stt.level,
                            transcript: stt.transcript,
                            statusMessage: statusText,
                            errorMessage: stt.errorMessage
                        ),
                        gestureArea: .fullSurface,
                        pauseBehavior: .enabled,
                        onFinish: { Task { await finishRecording() } },
                        onPause: { stt.pause() },
                        onResume: { stt.resume() }
                    )
                    .transition(.opacity)
                    .ignoresSafeArea()
                }
            }
        }
        .task { await startRecording() }
        .onReceive(NotificationCenter.default.publisher(for: .coachProposalDidChange)) { _ in
            reloadThread()
        }
    }

    // MARK: - Thread

    private var threadScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if sessionItems.isEmpty {
                        emptyHint
                    } else {
                        ForEach(sessionItems) { item in
                            threadCell(for: item)
                        }
                    }

                    if phase == .thinking {
                        thinkingBubble
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: threadItems.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: phase) { _, p in
                if p == .thinking {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    private var sessionItems: [ThreadItem] {
        threadItems.filter { $0.createdAt >= sessionStartDate }
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 60)
            Image(systemName: "brain.head.profile")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Tap the mic to ask anything")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func threadCell(for item: ThreadItem) -> some View {
        switch item {
        case .note(let note):
            NoteBubble(note: note)
        case .proposal(let proposal):
            ProposalThreadCard(proposal: proposal, onUpdate: reloadThread)
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

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        switch phase {
        case .idle:
            micBar()
        case .failed(let msg):
            micBar(errorMessage: msg)
        default:
            EmptyView()
        }
    }

    private func micBar(errorMessage: String? = nil) -> some View {
        VStack(spacing: 8) {
            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button {
                Task { await startRecording() }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor, in: Circle())
            }
            .accessibilityLabel("Record a message")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }

    // MARK: - Recording

    private var statusText: String {
        if stt.isStarting { return "Starting…" }
        if stt.isPaused { return "Paused" }
        return stt.statusMessage
    }

    private func startRecording() async {
        guard !stt.isRecording, !stt.isStarting else { return }
        phase = .recording
        do {
            try await stt.start(modelID: sttModel)
        } catch {
            stt.recordStartFailure(error)
            phase = .failed(stt.errorMessage ?? "Could not start recording.")
        }
    }

    private func finishRecording() async {
        let rawText = await stt.stop()
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            phase = .idle
            return
        }

        let cutStart = ActiveCutStore.load()?.startDate
        services.coachAuditStore.appendNote(
            source: .user,
            kind: .checkIn,
            visibility: .userVisible,
            cutStartDate: cutStart,
            day: Date(),
            text: text
        )
        reloadThread()

        phase = .thinking

        if !hasStartedConversation {
            conversationMessages = services.coachAgent.buildInitialMessages()
            hasStartedConversation = true
        }

        let userMessage: [String: Any] = ["role": "user", "content": text]
        let result = await services.coachAgent.runTurn(
            messages: conversationMessages,
            userMessage: userMessage,
            imageAttached: false
        )
        conversationMessages = result.messages

        guard let replyText = result.finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !replyText.isEmpty
        else {
            phase = .failed("Coach didn't return a reply.")
            return
        }

        services.coachAuditStore.appendNote(
            source: .agent,
            kind: .observation,
            visibility: .userVisible,
            cutStartDate: cutStart,
            day: Date(),
            text: replyText
        )
        NotificationCenter.default.post(name: .coachProposalDidChange, object: nil)
        reloadThread()

        phase = .idle
    }

    // MARK: - Data

    private func reloadThread() {
        var result: [ThreadItem] = []
        let notes = services.coachAuditStore.recentNotes(limit: 150, userVisibleOnly: true)
        result += notes.map { ThreadItem.note($0) }
        if let cut = ActiveCutStore.load() {
            let proposals = services.coachProposalStore.allProposals(forCutStartDate: cut.startDate)
            result += proposals.map { ThreadItem.proposal($0) }
        }
        threadItems = result.sorted { $0.createdAt < $1.createdAt }
    }
}
