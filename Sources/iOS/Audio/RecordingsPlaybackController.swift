import AVFoundation
import Combine
import Foundation

@MainActor
final class RecordingsPlaybackController: NSObject, ObservableObject {
    @Published private(set) var playingID: UUID?
    @Published private(set) var progress: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    func togglePlayPause(recording: VoiceRecordingDraft) {
        if playingID == recording.id {
            if isPlaying { pause() } else { resume() }
        } else {
            play(recording: recording)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
        progress = 0
        duration = 0
        isPlaying = false
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        progress = time
    }

    func skipBack() {
        seek(to: max(0, (player?.currentTime ?? 0) - 15))
    }

    func skipForward() {
        let cur = player?.currentTime ?? 0
        let dur = player?.duration ?? 0
        seek(to: min(dur, cur + 15))
    }

    private func play(recording: VoiceRecordingDraft) {
        let url = VoiceRecordingDraftStore.shared.url(for: recording)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        stop()
        do {
            try AudioSession.configureForPlayback()
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            playingID = recording.id
            duration = p.duration
            progress = 0
            isPlaying = true
            startTimer()
        } catch {}
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    private func resume() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    private func startTimer() {
        stopTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.progress = self?.player?.currentTime ?? 0
            }
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

extension RecordingsPlaybackController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.playingID = nil
            self?.isPlaying = false
            self?.progress = 0
            self?.stopTimer()
        }
    }
}
