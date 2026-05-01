import SwiftUI

struct VoiceCheckInSheet: View {
    @ObservedObject var stt: ElevenLabsRealtimeSTT

    var onFinish: () -> Void
    var onPause: () -> Void
    var onResume: () -> Void

    @State private var currentPressID: UUID?
    @State private var pauseActivated = false

    private static let pauseActivationDelay: TimeInterval = 0.18

    private var primaryIcon: String {
        if stt.isPaused { return "pause.fill" }
        return stt.isStarting ? "mic.circle" : "mic.fill"
    }

    private var hint: String {
        if stt.isPaused { return "Release to resume" }
        return "Tap to finish · hold to pause"
    }

    var body: some View {
        ZStack {
            VoiceWaveBackground(level: stt.level)
                .allowsHitTesting(false)
                .opacity(stt.isPaused ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.18), value: stt.isPaused)

            VStack(spacing: 16) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 10)
                    .contentTransition(.symbolEffect(.replace))

                Text(stt.transcript.isEmpty ? statusText : stt.transcript)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(.horizontal, 28)

                if let error = stt.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 28)
                }

                Spacer(minLength: 0)

                Text(hint)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)
                    .animation(.easeInOut(duration: 0.18), value: stt.isPaused)
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(pressGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stt.isPaused ? "Paused. Release to resume." : "Recording. Tap to finish, hold to pause.")
        .accessibilityAddTraits(.isButton)
    }

    private var statusText: String {
        if stt.isStarting { return "Starting…" }
        if stt.isPaused { return "Paused" }
        return stt.statusMessage
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard currentPressID == nil else { return }
                let id = UUID()
                currentPressID = id
                pauseActivated = false
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.pauseActivationDelay) {
                    guard currentPressID == id else { return }
                    pauseActivated = true
                    onPause()
                }
            }
            .onEnded { _ in
                let wasPaused = pauseActivated
                currentPressID = nil
                pauseActivated = false
                if wasPaused {
                    onResume()
                } else {
                    onFinish()
                }
            }
    }
}

private struct VoiceWaveBackground: View {
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
    }
}
