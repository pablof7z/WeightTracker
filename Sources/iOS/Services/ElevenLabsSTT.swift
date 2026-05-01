import Foundation

struct ElevenLabsSTT: Sendable {
    var modelID: String

    func transcribe(audioURL: URL) async throws -> String {
        guard let key = ElevenLabsCredentialStore.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        else {
            throw ProviderError.missingKey(provider: "ElevenLabs")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipartField("model_id", value: speechToTextModelID(from: modelID), boundary: boundary)
        let fileData = try Data(contentsOf: audioURL)
        body.appendMultipartFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            mime: mimeType(for: audioURL),
            data: fileData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, _) = try await HTTP.send(request)
        do {
            let response = try JSONDecoder().decode(SpeechToTextResponse.self, from: data)
            return response.text
        } catch {
            throw ProviderError.decoding(error.localizedDescription)
        }
    }

    private func speechToTextModelID(from configuredModelID: String) -> String {
        let model = configuredModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty || model == "scribe_v2_realtime" {
            return "scribe_v2"
        }
        return model
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/m4a"
        default:
            return "application/octet-stream"
        }
    }
}

private struct SpeechToTextResponse: Decodable {
    let text: String
}

private extension Data {
    mutating func appendMultipartField(_ name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append(value.data(using: .utf8)!)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(name: String, filename: String, mime: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
