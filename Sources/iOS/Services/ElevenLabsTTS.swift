import Foundation

/// Synthesizes speech via the ElevenLabs text-to-speech REST API.
///
/// Returns the raw MP3 bytes so the caller can play them directly with
/// `AVAudioPlayer(data:)` without writing a temp file.
struct ElevenLabsTTS: Sendable {
    static let defaultModelID = "eleven_turbo_v2_5"
    static let defaultOutputFormat = "mp3_44100_128"

    static func synthesize(
        text: String,
        voiceID: String,
        modelID: String = defaultModelID,
        outputFormat: String = defaultOutputFormat
    ) async throws -> Data {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ProviderError.audio("Cannot synthesize empty text.")
        }

        let trimmedVoice = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedVoice = trimmedVoice.isEmpty ? AppConstants.defaultElevenLabsVoiceID : trimmedVoice

        guard let key = ElevenLabsCredentialStore.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        else {
            throw ProviderError.missingKey(provider: "ElevenLabs")
        }

        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(resolvedVoice)?output_format=\(outputFormat)"
        guard let url = URL(string: urlString) else {
            throw ProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": trimmedText,
            "model_id": modelID
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw ProviderError.audio("Could not encode TTS request body: \(error.localizedDescription)")
        }

        let (data, _) = try await HTTP.send(request)
        guard !data.isEmpty else {
            throw ProviderError.invalidResponse
        }
        return data
    }
}
