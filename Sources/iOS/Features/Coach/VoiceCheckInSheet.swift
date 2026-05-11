import SwiftUI
import VoiceCaptureKit

struct VoiceCheckInSheet: View {
    @ObservedObject var stt: ElevenLabsRealtimeSTT

    var onFinish: () -> Void
    var onPause: () -> Void
    var onResume: () -> Void

    @Namespace private var voiceMicNS

    var body: some View {
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
            micTransitionSourceID: "voice.mic",
            micTransitionNamespace: voiceMicNS,
            onFinish: onFinish,
            onPause: onPause,
            onResume: onResume
        )
        .zoomNavigationTransition(sourceID: "voice.mic", in: voiceMicNS)
    }

    private var statusText: String {
        if stt.isStarting { return "Starting…" }
        if stt.isPaused { return "Paused" }
        return stt.statusMessage
    }
}
