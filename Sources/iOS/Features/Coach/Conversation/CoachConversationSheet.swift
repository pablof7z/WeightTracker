import SwiftUI
import UIKit

/// Adaptive sheet that hosts an end-to-end voice conversation with the coach.
/// Recording → Thinking → Speaking → Reply → Recording … the conversation
/// history is preserved across turns so the model has full context.
struct CoachConversationSheet: View {
    @StateObject private var controller: CoachConversationController
    @State private var showCamera: Bool = false
    @Environment(\.dismiss) private var dismiss

    @Namespace private var sheetNamespace

    init(agentSession: CoachAgentSession, sttModel: String, voiceID: String) {
        _controller = StateObject(wrappedValue: CoachConversationController(
            agentSession: agentSession,
            sttModel: sttModel,
            voiceID: voiceID
        ))
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                content
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task { await controller.startRecording() }
        }
        .onDisappear {
            controller.teardown()
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
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        switch controller.state {
        case .recording, .failed:
            ConversationWaveBackground(level: controller.stt.level)
                .opacity(controller.stt.isPaused ? 0.5 : 1)
                .animation(.easeInOut(duration: 0.18), value: controller.stt.isPaused)
                .allowsHitTesting(false)
        case .thinking:
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.18)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        case .speaking:
            LinearGradient(
                colors: [Color.black.opacity(0.92), Color.accentColor.opacity(0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .glass(in: Circle())
            }
            .accessibilityLabel("Close coach conversation")

            Spacer()

            if isRecordingMode {
                cameraButton
            }
        }
    }

    private var isRecordingMode: Bool {
        if case .recording = controller.state { return true }
        if case .failed = controller.state { return true }
        return false
    }

    @ViewBuilder
    private var cameraButton: some View {
        Button {
            showCamera = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let img = controller.capturedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                            )
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .glass(in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                if controller.capturedImage != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                        .background(Circle().fill(Color(.systemBackground)))
                        .offset(x: 4, y: 4)
                }
            }
        }
        .accessibilityLabel(controller.capturedImage == nil ? "Take a photo" : "Replace photo")
    }

    // MARK: - Content (state-dependent center stack)

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .recording:
            recordingContent
        case .thinking:
            thinkingContent
        case .speaking(let text):
            speakingContent(text: text)
        case .failed(let message):
            failedContent(message: message)
        }
    }

    @ViewBuilder
    private var recordingContent: some View {
        VStack(spacing: 18) {
            LiquidGlassContainer(spacing: 24) {
                Image(systemName: controller.stt.isPaused ? "pause.fill" : "mic.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(28)
                    .glass(in: Circle(), tint: controller.stt.isPaused ? .orange : .accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }

            Text(transcriptDisplayText)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(6)
                .padding(.horizontal, 12)

            if let error = controller.stt.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
            }

            if let img = controller.capturedImage {
                HStack(spacing: 8) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                .glass(in: Capsule())
            }
        }
    }

    private var transcriptDisplayText: String {
        if !controller.stt.transcript.isEmpty { return controller.stt.transcript }
        if controller.stt.isStarting { return "Starting…" }
        if controller.stt.isPaused { return "Paused" }
        return "Listening — speak when ready"
    }

    private var thinkingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .padding(.bottom, 6)
            Text("Coach is thinking…")
                .font(.headline)
                .foregroundStyle(.primary)
            if !controller.transcript.isEmpty {
                Text("\u{201C}\(controller.transcript)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func speakingContent(text: String) -> some View {
        VStack(spacing: 18) {
            ScrollView {
                Text(text)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .frame(maxHeight: 280)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 4)

            playbackControls
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, geo.size.width * controller.audioProgress), height: 4)
                }
            }
            .frame(height: 4)

            HStack(spacing: 20) {
                Button {
                    controller.replayAudio()
                } label: {
                    Image(systemName: "gobackward")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("Replay coach response")

                Button {
                    controller.togglePlayback()
                } label: {
                    Image(systemName: controller.isPlayingAudio ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Color.accentColor))
                }
                .accessibilityLabel(controller.isPlayingAudio ? "Pause coach" : "Play coach")
                .disabled(controller.audioFinished)
                .opacity(controller.audioFinished ? 0.4 : 1)

                Button {
                    controller.skipPlayback()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("Skip to end")
                .disabled(controller.audioFinished)
                .opacity(controller.audioFinished ? 0.4 : 1)
            }
        }
    }

    private func failedContent(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    // MARK: - Bottom bar (CTA)

    @ViewBuilder
    private var bottomBar: some View {
        switch controller.state {
        case .recording:
            recordingBottomBar
        case .thinking:
            EmptyView()
        case .speaking:
            speakingBottomBar
        case .failed:
            failedBottomBar
        }
    }

    private var recordingBottomBar: some View {
        VStack(spacing: 10) {
            Button {
                Task { await controller.sendTurn() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                    Text("Send")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(sendButtonEnabled ? Color.accentColor : Color.gray.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!sendButtonEnabled)

            Text("Tap mic when you're done · or tap Send")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var sendButtonEnabled: Bool {
        let hasTranscript = !controller.stt.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = controller.capturedImage != nil
        return (hasTranscript || hasImage)
            && !controller.stt.isStarting
    }

    private var speakingBottomBar: some View {
        Button {
            controller.startReply()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                Text("Reply")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(controller.audioFinished ? Color.accentColor : Color.white.opacity(0.18))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!controller.audioFinished)
        .opacity(controller.audioFinished ? 1 : 0.7)
    }

    private var failedBottomBar: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await controller.startRecording()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try again")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            Button {
                dismiss()
            } label: {
                Text("Dismiss")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Wave background (kept private to avoid clashing with VoiceCheckInSheet)

private struct ConversationWaveBackground: View {
    var level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let driven = max(0, min(1, Double(level)))
            Canvas { context, size in
                let baseY = size.height / 2
                let idleAmp: CGFloat = 8
                let liveAmp = CGFloat(driven) * size.height * 0.42
                let amp = idleAmp + liveAmp
                let layers: [(speed: Double, freq: Double, offset: Double, scale: CGFloat, opacity: Double)] = [
                    (1.7, 1.4, 0.0, 1.00, 0.55),
                    (1.1, 2.2, 1.3, 0.62, 0.32),
                    (0.6, 3.0, 2.6, 0.38, 0.18)
                ]
                for layer in layers {
                    var path = Path()
                    let steps = max(60, Int(size.width / 3))
                    for i in 0...steps {
                        let progress = Double(i) / Double(steps)
                        let x = CGFloat(progress) * size.width
                        let envelope = sin(progress * .pi)
                        let y = baseY + sin(progress * .pi * 2 * layer.freq + t * layer.speed + layer.offset)
                            * Double(amp * layer.scale) * envelope
                        let point = CGPoint(x: x, y: CGFloat(y))
                        if i == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    context.stroke(
                        path,
                        with: .color(Color.accentColor.opacity(layer.opacity)),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}
