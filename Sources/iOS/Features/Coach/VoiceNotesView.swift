import AVFoundation
import SwiftUI

// MARK: - Root

struct VoiceNotesView: View {
    var scrollToID: UUID? = nil

    @ObservedObject private var store = VoiceRecordingDraftStore.shared
    @StateObject private var playback = RecordingsPlaybackController()
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel = AppConstants.defaultElevenLabsSTTModel

    @State private var expandedID: UUID?
    @State private var pendingDeleteID: UUID?
    @State private var retryingIDs: Set<UUID> = []
    @State private var retryErrors: [UUID: String] = [:]
    @State private var showBulkRetryConfirm = false

    private var restorable: [VoiceRecordingDraft] {
        store.recordings.filter { $0.isRestorable }
    }

    private var attentionCount: Int {
        restorable.filter { $0.status == .failed || $0.status == .needsTranscription }.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.recordings) { recording in
                            RecordingRow(
                                recording: recording,
                                playback: playback,
                                isExpanded: expandedID == recording.id,
                                isRetrying: retryingIDs.contains(recording.id),
                                retryError: retryErrors[recording.id],
                                onToggleExpand: { toggleExpand(recording.id) },
                                onRetry: { retry(recording) },
                                onDelete: { pendingDeleteID = recording.id }
                            )
                            .id(recording.id)
                        }
                    } header: {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .textCase(nil)
                    }
                }

                if !restorable.isEmpty {
                    Section {
                        EmptyView()
                    } footer: {
                        Label("Voice notes are stored only on this device.", systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if restorable.isEmpty { emptyState }
            }
            .onAppear {
                guard let id = scrollToID else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                    expandedID = id
                }
            }
        }
        .navigationTitle("Voice Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if attentionCount >= 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showBulkRetryConfirm = true } label: {
                        Label("Retry all", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .confirmationDialog(
            "Retry transcription for \(attentionCount) voice notes?",
            isPresented: $showBulkRetryConfirm,
            titleVisibility: .visible
        ) {
            Button("Retry All") { retryAll() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete this voice note?", isPresented: Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID { store.delete(id: id) }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("The audio file and transcript will be permanently removed from this device. This can't be undone.")
        }
        .onDisappear { playback.stop() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text("No voice notes yet")
                .font(.title3.weight(.semibold))
            Text("When you check in with Coach, your voice is saved here automatically. Even if transcription fails, your audio stays safe on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -40)
    }

    // MARK: - Sections

    private struct DateSection {
        let title: String
        let recordings: [VoiceRecordingDraft]
    }

    private var sections: [DateSection] {
        let cal = Calendar.current
        let now = Date()
        var today: [VoiceRecordingDraft] = []
        var yesterday: [VoiceRecordingDraft] = []
        var thisWeek: [VoiceRecordingDraft] = []
        var earlier: [VoiceRecordingDraft] = []

        for r in restorable {
            if cal.isDateInToday(r.createdAt) {
                today.append(r)
            } else if cal.isDateInYesterday(r.createdAt) {
                yesterday.append(r)
            } else if cal.dateComponents([.day], from: r.createdAt, to: now).day ?? 8 < 7 {
                thisWeek.append(r)
            } else {
                earlier.append(r)
            }
        }

        return [
            DateSection(title: "Today", recordings: today),
            DateSection(title: "Yesterday", recordings: yesterday),
            DateSection(title: "This Week", recordings: thisWeek),
            DateSection(title: "Earlier", recordings: earlier),
        ].filter { !$0.recordings.isEmpty }
    }

    // MARK: - Actions

    private func toggleExpand(_ id: UUID) {
        withAnimation(.smooth(duration: 0.3)) {
            expandedID = expandedID == id ? nil : id
        }
    }

    private func retry(_ recording: VoiceRecordingDraft) {
        guard !retryingIDs.contains(recording.id) else { return }
        retryingIDs.insert(recording.id)
        retryErrors.removeValue(forKey: recording.id)
        let url = store.url(for: recording)
        let model = sttModel
        Task {
            do {
                let transcript = try await ElevenLabsSTT(modelID: model).transcribe(audioURL: url)
                await MainActor.run {
                    store.markTranscribed(id: recording.id, transcript: transcript)
                    retryingIDs.remove(recording.id)
                }
            } catch {
                let message: String
                if case ProviderError.missingKey = error {
                    message = "Add an ElevenLabs API key in Settings to transcribe."
                } else {
                    message = "Couldn't reach the transcription service. Your audio is still saved."
                }
                await MainActor.run {
                    retryErrors[recording.id] = message
                    retryingIDs.remove(recording.id)
                }
            }
        }
    }

    private func retryAll() {
        for r in restorable where r.status == .failed || r.status == .needsTranscription {
            retry(r)
        }
    }
}

// MARK: - Row

private struct RecordingRow: View {
    let recording: VoiceRecordingDraft
    let playback: RecordingsPlaybackController
    let isExpanded: Bool
    let isRetrying: Bool
    let retryError: String?
    let onToggleExpand: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void

    private var isPlaying: Bool { playback.playingID == recording.id && playback.isPlaying }
    private var isThisPlaying: Bool { playback.playingID == recording.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedRow
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.3), value: isExpanded)
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .listRowBackground(rowBackground)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggleExpand() }
    }

    // MARK: Collapsed row

    private var collapsedRow: some View {
        HStack(spacing: 12) {
            leadingIcon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(dateLabel)
                    .font(.subheadline.weight(.medium))
                transcriptLine
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatTime(recording.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                statusPill
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch recording.status {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.orange.opacity(0.12)))
        case .needsTranscription:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.secondary.opacity(0.1)))
        case .recording:
            Image(systemName: "mic.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.red.opacity(0.12)))
        case .transcribed:
            Button {
                playback.togglePlayPause(recording: recording)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) {
                if isThisPlaying && !isExpanded {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .overlay(alignment: .leading) {
                            let fraction = playback.duration > 0 ? playback.progress / playback.duration : 0
                            Capsule()
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(width: CGFloat(fraction) * 36)
                        }
                        .offset(y: 6)
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptLine: some View {
        switch recording.status {
        case .transcribed:
            if let t = recording.transcript, !t.isEmpty {
                Text(t)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        case .failed:
            Text("Transcription unavailable. Audio is saved.")
                .font(.footnote.italic())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        case .needsTranscription:
            Text("Transcribing soon…")
                .font(.footnote.italic())
                .foregroundStyle(.secondary)
        case .recording:
            Text("Recording in progress…")
                .font(.footnote.italic())
                .foregroundStyle(.red.opacity(0.7))
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch recording.status {
        case .transcribed:
            EmptyView()
        case .failed:
            PillLabel(text: "Tap to retry", color: .orange)
        case .needsTranscription:
            PillLabel(text: "Pending", color: .secondary)
        case .recording:
            PillLabel(text: "Recording", color: .red)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        switch recording.status {
        case .failed:
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.06))
        default:
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            if let transcript = recording.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if recording.status == .transcribed {
                playbackControls
            }

            if recording.status == .failed || recording.status == .needsTranscription {
                retrySection
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var playbackControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(formatTime(isThisPlaying ? playback.progress : 0))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { isThisPlaying ? playback.progress : 0 },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(1, isThisPlaying ? playback.duration : recording.duration)
                )
                .tint(.accentColor)
                Text(formatTime(isThisPlaying ? playback.duration : recording.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            HStack(spacing: 28) {
                Button { playback.skipBack() } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                        .foregroundStyle(isThisPlaying ? .primary : .secondary)
                }
                .disabled(!isThisPlaying)

                Button {
                    playback.togglePlayPause(recording: recording)
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                }

                Button { playback.skipForward() } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                        .foregroundStyle(isThisPlaying ? .primary : .secondary)
                }
                .disabled(!isThisPlaying)

                Spacer()

                ShareLink(item: VoiceRecordingDraftStore.shared.url(for: recording)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var retrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onRetry) {
                HStack {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                        Text("Transcribing…")
                    } else {
                        Label("Retry transcription", systemImage: "arrow.clockwise")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()
            .tint(.orange)
            .disabled(isRetrying)

            if let err = retryError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let msg = recording.failureMessage {
                DisclosureGroup("Why did this fail?") {
                    Text(msg)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Helpers

    private var dateLabel: String {
        let cal = Calendar.current
        let d = recording.createdAt
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(d) { return "Today, \(time)" }
        if cal.isDateInYesterday(d) { return "Yesterday, \(time)" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Pill

private struct PillLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

// MARK: - Formatters

private func formatTime(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    return String(format: "%d:%02d", s / 60, s % 60)
}
