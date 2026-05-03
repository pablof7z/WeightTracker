import AVFoundation
import Combine
import Foundation
import UIKit

/// Drives the back-and-forth voice conversation between the user and the
/// coach. Owns the STT pipeline, the OpenRouter turn invocation, the
/// ElevenLabs TTS request, and the AVAudioPlayer that plays the response.
///
/// The view is intentionally dumb — it observes published state and forwards
/// taps. All audio session juggling and message-history bookkeeping lives
/// here so the SwiftUI body stays declarative.
@MainActor
final class CoachConversationController: NSObject, ObservableObject {
    enum State: Equatable {
        case recording
        case thinking
        case speaking(text: String)
        case failed(message: String)
    }

    @Published private(set) var state: State = .recording
    @Published private(set) var transcript: String = ""
    @Published private(set) var capturedImage: UIImage? = nil
    @Published private(set) var isPlayingAudio: Bool = false
    @Published private(set) var audioFinished: Bool = false
    @Published private(set) var audioProgress: Double = 0
    @Published private(set) var audioDuration: TimeInterval = 0

    let stt: ElevenLabsRealtimeSTT
    private let agentSession: CoachAgentSession
    private let sttModel: String
    private let voiceID: String

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private var conversationMessages: [[String: Any]] = []
    private var hasStartedConversation: Bool = false

    init(
        agentSession: CoachAgentSession,
        sttModel: String,
        voiceID: String,
        stt: ElevenLabsRealtimeSTT = ElevenLabsRealtimeSTT()
    ) {
        self.agentSession = agentSession
        self.sttModel = sttModel
        self.voiceID = voiceID
        self.stt = stt
        super.init()
    }

    // MARK: - Recording

    func startRecording() async {
        guard !stt.isRecording, !stt.isStarting else { return }
        do {
            try await stt.start(modelID: sttModel)
        } catch {
            stt.recordStartFailure(error)
            state = .failed(message: stt.errorMessage ?? "Could not start recording.")
        }
    }

    func pauseRecording() { stt.pause() }
    func resumeRecording() { stt.resume() }

    func setCapturedImage(_ image: UIImage?) {
        capturedImage = image
    }

    // MARK: - Send turn

    /// Stop recording, transcribe, send to coach, get TTS, and play it back.
    /// On error: surfaces a `.failed(...)` state with the message.
    func sendTurn() async {
        let recordedText = await stt.stop()
        let trimmedTranscript = recordedText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = trimmedTranscript

        if trimmedTranscript.isEmpty && capturedImage == nil {
            state = .failed(message: "Nothing to send. Tap Reply to try again.")
            return
        }

        let imageForTurn = capturedImage
        let messageText = trimmedTranscript.isEmpty
            ? "(no spoken message — see attached photo)"
            : trimmedTranscript
        let userMessage = buildUserMessage(text: messageText, image: imageForTurn)

        if !hasStartedConversation {
            conversationMessages = agentSession.buildInitialMessages()
            hasStartedConversation = true
        }

        state = .thinking
        let turnResult = await agentSession.runTurn(
            messages: conversationMessages,
            userMessage: userMessage,
            imageAttached: imageForTurn != nil
        )
        conversationMessages = turnResult.messages

        guard let finalText = turnResult.finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !finalText.isEmpty
        else {
            state = .failed(message: "Coach didn't return a reply. Tap Reply to try again.")
            return
        }

        do {
            let audioData = try await ElevenLabsTTS.synthesize(text: finalText, voiceID: voiceID)
            try playAudio(data: audioData)
            state = .speaking(text: finalText)
        } catch let providerError as ProviderError {
            state = .failed(message: providerError.errorDescription ?? "TTS failed.")
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Playback controls

    func pausePlayback() {
        audioPlayer?.pause()
        isPlayingAudio = false
        stopProgressTimer()
    }

    func resumePlayback() {
        guard let audioPlayer else { return }
        audioPlayer.play()
        isPlayingAudio = true
        startProgressTimer()
    }

    func togglePlayback() {
        if isPlayingAudio { pausePlayback() } else { resumePlayback() }
    }

    func replayAudio() {
        guard let audioPlayer else { return }
        audioPlayer.currentTime = 0
        audioPlayer.play()
        isPlayingAudio = true
        audioFinished = false
        audioProgress = 0
        startProgressTimer()
    }

    func skipPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
        audioFinished = true
        audioProgress = 1
        stopProgressTimer()
    }

    /// Move from speaking-mode back to recording-mode and immediately begin
    /// listening again. The audio player is torn down; the conversation
    /// history persists so the coach has full context.
    func startReply() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
        audioFinished = false
        audioProgress = 0
        audioDuration = 0
        stopProgressTimer()
        capturedImage = nil
        transcript = ""
        state = .recording
        Task { await self.startRecording() }
    }

    // MARK: - Cleanup

    func teardown() {
        if stt.isRecording || stt.isStarting { stt.cancel() }
        audioPlayer?.stop()
        audioPlayer = nil
        stopProgressTimer()
        AudioSession.deactivate()
    }

    // MARK: - Private helpers

    private func buildUserMessage(text: String, image: UIImage?) -> [String: Any] {
        guard let image else {
            return ["role": "user", "content": text]
        }
        let resized = image.resizedForCoach(maxDimension: 1024)
        let jpegData = resized.jpegData(compressionQuality: 0.7) ?? Data()
        let b64 = jpegData.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(b64)"
        return [
            "role": "user",
            "content": [
                ["type": "text", "text": text],
                ["type": "image_url", "image_url": ["url": dataURL]]
            ]
        ]
    }

    private func playAudio(data: Data) throws {
        try AudioSession.configureForPlayback()
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        audioPlayer = player
        audioDuration = player.duration
        audioProgress = 0
        audioFinished = false
        if player.play() {
            isPlayingAudio = true
            startProgressTimer()
        } else {
            isPlayingAudio = false
            throw ProviderError.audio("AVAudioPlayer refused to start playback.")
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.audioPlayer else { return }
                if player.duration > 0 {
                    self.audioProgress = min(1, player.currentTime / player.duration)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

extension CoachConversationController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlayingAudio = false
            self.audioFinished = true
            self.audioProgress = 1
            self.stopProgressTimer()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isPlayingAudio = false
            self.audioFinished = true
            self.stopProgressTimer()
            self.state = .failed(message: error?.localizedDescription ?? "Playback decode error.")
        }
    }
}
