import SwiftUI
import UIKit

/// Text-first conversation sheet. Voice input is optional — users can dictate
/// or type. Coach replies always appear as text; there is no TTS playback.
struct CoachConversationSheet: View {
    @StateObject private var controller: CoachConversationController
    @State private var showCamera: Bool = false
    @Environment(\.dismiss) private var dismiss

    init(agentSession: CoachAgentSession, sttModel: String, auditStore: CoachAuditStore? = nil) {
        _controller = StateObject(wrappedValue: CoachConversationController(
            agentSession: agentSession,
            sttModel: sttModel,
            auditStore: auditStore,
            autoResetAfterReply: false
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                    inputBar
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemBackground))
                }
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    cameraButton
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView(
                image: Binding(
                    get: { controller.capturedImage },
                    set: { controller.setCapturedImage($0) }
                ),
                onDismiss: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .onDisappear { controller.teardown() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .composing:
            composingContent
        case .thinking:
            thinkingContent
        case .replied(let text):
            repliedContent(text: text)
        case .failed(let message):
            failedContent(message: message)
        }
    }

    private var composingContent: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Ask the coach anything")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Type below or tap the mic to speak")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            if controller.capturedImage != nil {
                photoAttachmentBadge
            }
            Spacer()
        }
        .padding()
    }

    private var thinkingContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("Coach is thinking…")
                .font(.headline)
                .foregroundStyle(.primary)
            if !controller.transcript.isEmpty {
                Text("\u{201C}\(controller.transcript)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    private func repliedContent(text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !controller.transcript.isEmpty {
                    HStack {
                        Spacer()
                        Text(controller.transcript)
                            .font(.subheadline)
                            .padding(12)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    ProposalCard.markdownText(text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
    }

    private func failedContent(message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Try again") {
                controller.resetToComposing()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Input bar

    @ViewBuilder
    private var inputBar: some View {
        switch controller.state {
        case .composing, .failed:
            composingInputBar
        case .thinking:
            EmptyView()
        case .replied:
            continueInputBar
        }
    }

    private var composingInputBar: some View {
        HStack(spacing: 10) {
            micButton
            TextField("Message coach…", text: $controller.inputText, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .onSubmit { sendIfReady() }

            sendButton
        }
    }

    private var continueInputBar: some View {
        HStack(spacing: 10) {
            micButton
            TextField("Reply…", text: $controller.inputText, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .onSubmit { sendIfReady() }
            sendButton
        }
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
        Button {
            sendIfReady()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
        }
        .disabled(!canSend)
        .accessibilityLabel("Send message")
    }

    private var canSend: Bool {
        let hasText = !controller.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = controller.capturedImage != nil
        let notThinking: Bool
        if case .thinking = controller.state { notThinking = false } else { notThinking = true }
        return (hasText || hasImage || controller.stt.isRecording) && notThinking
    }

    private func sendIfReady() {
        guard canSend else { return }
        Task { await controller.sendTurn() }
    }

    private func handleMicTap() async {
        if controller.stt.isRecording || controller.stt.isStarting {
            await controller.stopRecording()
        } else {
            await controller.startRecording()
        }
    }

    // MARK: - Camera

    @ViewBuilder
    private var cameraButton: some View {
        Button {
            showCamera = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let img = controller.capturedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                        )
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                        .background(Circle().fill(Color(.systemBackground)))
                        .offset(x: 3, y: 3)
                } else {
                    Image(systemName: "camera")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel(controller.capturedImage == nil ? "Attach photo" : "Replace photo")
    }

    private var photoAttachmentBadge: some View {
        HStack(spacing: 8) {
            if let img = controller.capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("Photo attached")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                controller.setCapturedImage(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}

