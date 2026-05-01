import AVFoundation
import Combine
import Foundation

@MainActor
final class ElevenLabsRealtimeSTT: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var isPaused = false
    @Published private(set) var level: Float = 0
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage = "Idle"
    @Published private(set) var currentRecordingID: UUID?

    private let sampleRate = 16_000
    private let vadSilenceThresholdSecs = 1.2
    private let vadThreshold = 0.4

    private var webSocketTask: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var audioCapture: RealtimeAudioCapture?
    private var localRecording: ActiveVoiceRecording?
    private var committedSegments: [String] = []
    private var partialTranscript = ""
    private var pendingAudioChunks: [Data] = []
    private var isSendingAudio = false
    private var shouldAcceptAudio = false
    private var shouldQueueAudio = false
    private var shouldSendAudio = false
    private var isClosing = false

    func start(modelID configuredModelID: String) async throws {
        guard !isRecording, !isStarting else { return }
        let key = ElevenLabsCredentialStore.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        isStarting = true
        statusMessage = "Preparing microphone"
        defer {
            isStarting = false
            if !isRecording, errorMessage == nil {
                statusMessage = "Idle"
            }
        }

        resetTranscript()
        errorMessage = nil
        isClosing = false
        currentRecordingID = nil
        pendingAudioChunks.removeAll()
        connectionTask?.cancel()

        shouldAcceptAudio = true
        shouldQueueAudio = key != nil
        shouldSendAudio = false
        isPaused = false

        do {
            try await startAudioCapture()
            currentRecordingID = localRecording?.id
            isRecording = true
            statusMessage = key == nil ? "Saving locally" : "Connecting to ElevenLabs"
        } catch {
            shouldAcceptAudio = false
            shouldQueueAudio = false
            shouldSendAudio = false
            closeSocket()
            throw error
        }

        guard let key else {
            statusMessage = "Saving locally. Add ElevenLabs key to transcribe."
            return
        }

        connectionTask = Task { @MainActor [weak self] in
            await self?.connectRealtime(apiKey: key, configuredModelID: configuredModelID)
        }
    }

    func stop() async -> String {
        guard isRecording || webSocketTask != nil else {
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        shouldAcceptAudio = false
        shouldQueueAudio = false
        connectionTask?.cancel()
        connectionTask = nil
        stopAudioCapture()
        isRecording = false
        isPaused = false
        statusMessage = "Finishing transcript"
        level = 0

        let deadline = Date().addingTimeInterval(1.0)
        while (isSendingAudio || !pendingAudioChunks.isEmpty) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        closeSocket()
        statusMessage = "Idle"
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        finishLocalRecording(
            transcript: text,
            failureMessage: text.isEmpty
                ? (errorMessage ?? "Recording saved. Retry transcription when you are online.")
                : nil
        )
        return text
    }

    func cancel() {
        shouldAcceptAudio = false
        shouldQueueAudio = false
        connectionTask?.cancel()
        connectionTask = nil
        stopAudioCapture()
        closeSocket()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        finishLocalRecording(
            transcript: text,
            failureMessage: text.isEmpty ? "Recording was saved before transcription finished." : nil
        )
        resetTranscript()
        isRecording = false
        isStarting = false
        isPaused = false
        statusMessage = "Idle"
        level = 0
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        shouldAcceptAudio = false
        level = 0
        statusMessage = "Paused"
    }

    func resume() {
        guard isRecording, isPaused else { return }
        isPaused = false
        shouldAcceptAudio = true
        statusMessage = "Listening"
    }

    func recordStartFailure(_ error: Error) {
        errorMessage = providerMessage(error)
        statusMessage = "Idle"
        isRecording = false
        isStarting = false
        isPaused = false
        level = 0
    }

    private func connectRealtime(apiKey: String, configuredModelID: String) async {
        do {
            let token = try await createRealtimeToken(apiKey: apiKey)
            try Task.checkCancellation()
            guard isRecording, shouldAcceptAudio else { return }

            let request = try makeWebSocketRequest(token: token, modelID: realtimeModelID(from: configuredModelID))
            let task = HTTP.session.webSocketTask(with: request)
            webSocketTask = task
            isClosing = false
            shouldSendAudio = true
            task.resume()

            receiveTask = Task { @MainActor [weak self] in
                await self?.receiveLoop()
            }
            statusMessage = "Listening"
            startDrainingAudioQueue()
        } catch is CancellationError {
            return
        } catch {
            guard isRecording || shouldAcceptAudio else { return }
            realtimeUnavailable(with: providerMessage(error))
        }
    }

    private func createRealtimeToken(apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/single-use-token/realtime_scribe") else {
            throw ProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, _) = try await HTTP.send(request)
        do {
            let response = try JSONDecoder().decode(SingleUseTokenResponse.self, from: data)
            guard !response.token.isEmpty else {
                throw ProviderError.invalidResponse
            }
            return response.token
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.decoding(error.localizedDescription)
        }
    }

    private func makeWebSocketRequest(token: String, modelID: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "api.elevenlabs.io"
        components.path = "/v1/speech-to-text/realtime"
        components.queryItems = [
            URLQueryItem(name: "model_id", value: modelID),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "vad"),
            URLQueryItem(name: "vad_silence_threshold_secs", value: "\(vadSilenceThresholdSecs)"),
            URLQueryItem(name: "vad_threshold", value: "\(vadThreshold)"),
            URLQueryItem(name: "include_timestamps", value: "false")
        ]

        guard let url = components.url else {
            throw ProviderError.invalidResponse
        }

        return URLRequest(url: url)
    }

    private func realtimeModelID(from configuredModelID: String) -> String {
        let modelID = configuredModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelID.isEmpty || modelID == "scribe_v2" {
            return "scribe_v2_realtime"
        }
        return modelID
    }

    private func startAudioCapture() async throws {
        try await AudioSession.configureForRealtimeRecording(sampleRate: Double(sampleRate))
        let recording = try VoiceRecordingDraftStore.shared.beginRecording(sampleRate: sampleRate)
        localRecording = recording

        let capture = RealtimeAudioCapture(
            sampleRate: sampleRate,
            packetSink: RealtimeAudioPacketSink(owner: self)
        )
        do {
            try capture.start()
            audioCapture = capture
        } catch {
            capture.stop()
            recording.handle.closeFile()
            recording.isClosed = true
            VoiceRecordingDraftStore.shared.delete(id: recording.id)
            localRecording = nil
            AudioSession.deactivate()
            throw error
        }
    }

    private func stopAudioCapture() {
        guard let audioCapture else { return }
        audioCapture.stop()
        self.audioCapture = nil
        AudioSession.deactivate()
    }

    fileprivate func handleAudioPacket(_ packet: AudioPacket) {
        guard shouldAcceptAudio else { return }
        level = packet.level
        if let localRecording {
            VoiceRecordingDraftStore.shared.append(packet.data, to: localRecording)
        }
        enqueueAudio(packet.data)
    }

    private func enqueueAudio(_ data: Data) {
        guard shouldAcceptAudio, shouldQueueAudio, !data.isEmpty else { return }
        pendingAudioChunks.append(data)
        startDrainingAudioQueue()
    }

    private func startDrainingAudioQueue() {
        guard shouldSendAudio, !isSendingAudio else { return }
        isSendingAudio = true
        Task { @MainActor [weak self] in
            await self?.drainAudioQueue()
        }
    }

    private func drainAudioQueue() async {
        while shouldSendAudio, !pendingAudioChunks.isEmpty {
            guard let webSocketTask else {
                pendingAudioChunks.removeAll()
                break
            }

            let data = pendingAudioChunks.removeFirst()
            do {
                try await sendAudio(data, through: webSocketTask)
            } catch {
                realtimeUnavailable(with: providerMessage(error))
                break
            }
        }

        isSendingAudio = false
        if shouldSendAudio, !pendingAudioChunks.isEmpty {
            startDrainingAudioQueue()
        }
    }

    private func sendAudio(_ data: Data, through webSocketTask: URLSessionWebSocketTask) async throws {
        let payload = InputAudioChunk(audioBase64: data.base64EncodedString(), sampleRate: sampleRate)
        let encoded = try JSONEncoder().encode(payload)
        guard let text = String(data: encoded, encoding: .utf8) else {
            throw ProviderError.invalidResponse
        }
        try await webSocketTask.send(.string(text))
    }

    private func receiveLoop() async {
        while !Task.isCancelled, let webSocketTask {
            do {
                let message = try await webSocketTask.receive()
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !isClosing {
                    realtimeUnavailable(with: providerMessage(error))
                }
                return
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let event = try JSONDecoder().decode(RealtimeEvent.self, from: data)
            switch event.messageType {
            case "partial_transcript":
                statusMessage = "Receiving transcript"
                partialTranscript = event.text ?? ""
                updateTranscript()
            case "committed_transcript", "committed_transcript_with_timestamps":
                statusMessage = "Receiving transcript"
                appendCommitted(event.text ?? "")
            case "session_started":
                statusMessage = "Listening"
            default:
                if event.messageType.contains("error") {
                    realtimeUnavailable(with: event.errorMessage)
                }
            }
        } catch {
            errorMessage = ProviderError.decoding(error.localizedDescription).localizedDescription
        }
    }

    private func appendCommitted(_ text: String) {
        let segment = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { return }
        committedSegments.append(segment)
        partialTranscript = ""
        updateTranscript()
    }

    private func updateTranscript() {
        var text = committedSegments.joined(separator: " ")
        let partial = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            text = text.isEmpty ? partial : "\(text) \(partial)"
        }
        transcript = text
    }

    private func realtimeUnavailable(with message: String) {
        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = detail.isEmpty
            ? "Live transcription unavailable. Recording is still being saved."
            : "\(detail) Recording is still being saved."
        statusMessage = isRecording ? "Saving locally" : "Idle"
        shouldQueueAudio = false
        shouldSendAudio = false
        pendingAudioChunks.removeAll()
        closeSocket()
    }

    private func closeSocket() {
        isClosing = true
        shouldSendAudio = false
        pendingAudioChunks.removeAll()
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isSendingAudio = false
    }

    private func resetTranscript() {
        transcript = ""
        partialTranscript = ""
        committedSegments = []
    }

    private func finishLocalRecording(transcript: String, failureMessage: String?) {
        guard let localRecording else { return }
        let draft = VoiceRecordingDraftStore.shared.finish(
            localRecording,
            transcript: transcript,
            failureMessage: failureMessage
        )
        currentRecordingID = draft?.id
        self.localRecording = nil
    }

    private func providerMessage(_ error: Error) -> String {
        if let providerError = error as? ProviderError {
            return providerError.localizedDescription
        }
        return ProviderError.network(error.localizedDescription).localizedDescription
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private final class RealtimeAudioCapture {
    private let sampleRate: Int
    private let packetSink: RealtimeAudioPacketSink
    private var audioEngine: AVAudioEngine?
    private var tapInstalled = false

    init(sampleRate: Int, packetSink: RealtimeAudioPacketSink) {
        self.sampleRate = sampleRate
        self.packetSink = packetSink
    }

    func start() throws {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw ProviderError.audio("Could not create realtime audio format.")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw ProviderError.audio("Could not prepare realtime audio conversion.")
        }
        converter.primeMethod = .none

        let tapBufferSize = AVAudioFrameCount(max(1024, min(8192, Int(inputFormat.sampleRate * 0.1))))
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [packetSink, converter, outputFormat] buffer, _ in
            guard let packet = Self.packet(from: buffer, converter: converter, outputFormat: outputFormat) else {
                return
            }
            packetSink.send(packet)
        }
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
    }

    private static func packet(
        from buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) -> AudioPacket? {
        let inputLevel = level(from: buffer)
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let convertedCapacity = Int(ceil(Double(buffer.frameLength) * ratio)) + 32
        let capacity = max(Int(buffer.frameLength), convertedCapacity, 1)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(capacity)
        ) else {
            return nil
        }

        let inputProvider = ConverterInputProvider(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.provideInput(status: inputStatus)
        }

        guard outputBuffer.frameLength > 0 else {
            switch status {
            case .haveData, .inputRanDry, .endOfStream, .error:
                return AudioPacket(data: Data(), level: inputLevel)
            @unknown default:
                return AudioPacket(data: Data(), level: inputLevel)
            }
        }

        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        let bytesPerFrame = Int(outputFormat.streamDescription.pointee.mBytesPerFrame)
        let byteCount = Int(outputBuffer.frameLength) * bytesPerFrame
        guard let bytes = audioBuffer.mData, byteCount > 0 else {
            return nil
        }

        let availableByteCount = min(byteCount, Int(audioBuffer.mDataByteSize))
        let data = Data(bytes: bytes, count: availableByteCount)
        return AudioPacket(data: data, level: max(inputLevel, level(from: data)))
    }

    private static func level(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        if let channels = buffer.floatChannelData {
            let channelCount = max(1, Int(buffer.format.channelCount))
            var sum: Float = 0
            var count = 0
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frameLength {
                    let sample = samples[frame]
                    sum += sample * sample
                    count += 1
                }
            }
            guard count > 0 else { return 0 }
            return min(1, sqrt(sum / Float(count)) * 8)
        }

        if let channels = buffer.int16ChannelData {
            let channelCount = max(1, Int(buffer.format.channelCount))
            var sum: Float = 0
            var count = 0
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frameLength {
                    let normalized = Float(samples[frame]) / Float(Int16.max)
                    sum += normalized * normalized
                    count += 1
                }
            }
            guard count > 0 else { return 0 }
            return min(1, sqrt(sum / Float(count)) * 8)
        }

        return 0
    }

    private static func level(from data: Data) -> Float {
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0 }

            var sum: Float = 0
            for sample in samples {
                let normalized = Float(sample) / Float(Int16.max)
                sum += normalized * normalized
            }
            let rms = sqrt(sum / Float(samples.count))
            return min(1, rms * 8)
        }
    }
}

private final class ConverterInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provideInput(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if didProvideInput {
            status.pointee = .noDataNow
            return nil
        }
        didProvideInput = true
        status.pointee = .haveData
        return buffer
    }
}

private final class RealtimeAudioPacketSink: @unchecked Sendable {
    private weak var owner: ElevenLabsRealtimeSTT?

    @MainActor
    init(owner: ElevenLabsRealtimeSTT) {
        self.owner = owner
    }

    func send(_ packet: AudioPacket) {
        let owner = owner
        Task { @MainActor in
            owner?.handleAudioPacket(packet)
        }
    }
}

fileprivate struct AudioPacket: Sendable {
    var data: Data
    var level: Float
}

private struct InputAudioChunk: Encodable {
    var messageType = "input_audio_chunk"
    var audioBase64: String
    var sampleRate: Int

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case audioBase64 = "audio_base_64"
        case sampleRate = "sample_rate"
    }
}

private struct SingleUseTokenResponse: Decodable {
    var token: String
}

private struct RealtimeEvent: Decodable {
    var messageType: String
    var text: String?
    var error: String?
    var message: String?
    var detail: String?

    var errorMessage: String {
        error ?? message ?? detail ?? "Realtime transcription failed."
    }

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case text
        case error
        case message
        case detail
    }
}
