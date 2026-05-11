import Combine
import Foundation
import UIKit

/// Drives a back-and-forth text conversation between the user and the coach.
/// Voice input (STT) is optional — the user can dictate or type. Coach
/// replies are always text; there is no TTS playback.
@MainActor
final class CoachConversationController: NSObject, ObservableObject {
    enum State: Equatable {
        case composing
        case thinking
        case replied(text: String)
        case failed(message: String)
    }

    @Published private(set) var state: State = .composing
    @Published private(set) var transcript: String = ""
    @Published private(set) var capturedImage: UIImage? = nil
    @Published var inputText: String = ""

    let stt: ElevenLabsRealtimeSTT
    private let agentSession: CoachAgentSession
    private let auditStore: CoachAuditStore?
    private let sttModel: String
    private let autoResetAfterReply: Bool

    private var conversationMessages: [[String: Any]] = []
    private var hasStartedConversation: Bool = false

    init(
        agentSession: CoachAgentSession,
        sttModel: String,
        auditStore: CoachAuditStore? = nil,
        autoResetAfterReply: Bool = false,
        stt: ElevenLabsRealtimeSTT = ElevenLabsRealtimeSTT()
    ) {
        self.agentSession = agentSession
        self.sttModel = sttModel
        self.auditStore = auditStore
        self.autoResetAfterReply = autoResetAfterReply
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

    func stopRecording() async {
        let text = await stt.stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            inputText = trimmed
        }
        transcript = trimmed
    }

    func setCapturedImage(_ image: UIImage?) {
        capturedImage = image
    }

    // MARK: - Send turn

    func sendTurn() async {
        if stt.isRecording || stt.isStarting {
            let text = await stt.stop()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { inputText = trimmed }
        }

        let textToSend = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageForTurn = capturedImage

        guard !textToSend.isEmpty || imageForTurn != nil else {
            state = .failed(message: "Nothing to send. Type a message or record your voice first.")
            return
        }

        transcript = textToSend
        inputText = ""

        let messageText = textToSend.isEmpty
            ? "(no text message — see attached photo)"
            : textToSend

        persistUserNote(text: textToSend.isEmpty ? "(photo sent)" : textToSend)

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
        capturedImage = nil

        guard let finalText = turnResult.finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !finalText.isEmpty
        else {
            state = .failed(message: "Coach didn't return a reply. Try again.")
            return
        }

        persistCoachNote(text: finalText)
        if autoResetAfterReply {
            state = .composing
            inputText = ""
            transcript = ""
        } else {
            state = .replied(text: finalText)
        }
    }

    // MARK: - Continue conversation

    func startNextTurn() {
        inputText = ""
        transcript = ""
        state = .composing
        Task { await startRecording() }
    }

    func resetToComposing() {
        state = .composing
    }

    // MARK: - Cleanup

    func teardown() {
        if stt.isRecording || stt.isStarting { stt.cancel() }
    }

    // MARK: - Private helpers

    private func persistUserNote(text: String) {
        guard let auditStore, !text.isEmpty else { return }
        let cutStart = ActiveCutStore.load()?.startDate
        auditStore.appendNote(
            source: .user,
            kind: .checkIn,
            visibility: .userVisible,
            cutStartDate: cutStart,
            day: Date(),
            text: text
        )
    }

    private func persistCoachNote(text: String) {
        guard let auditStore, !text.isEmpty else { return }
        let cutStart = ActiveCutStore.load()?.startDate
        auditStore.appendNote(
            source: .agent,
            kind: .observation,
            visibility: .userVisible,
            cutStartDate: cutStart,
            day: Date(),
            text: text
        )
        NotificationCenter.default.post(name: .coachProposalDidChange, object: nil)
    }

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
}
