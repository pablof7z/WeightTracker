import Foundation

enum CoachOpenRouterError: LocalizedError {
    case missingAPIKey
    case invalidTools(String)
    case invalidResponse(String)
    case httpStatus(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No OpenRouter key is connected."
        case .invalidTools(let message):
            return "Invalid tool schema: \(message)"
        case .invalidResponse(let message):
            return "OpenRouter returned an invalid response: \(message)"
        case .httpStatus(let status, let body):
            return "OpenRouter failed with HTTP \(status): \(body)"
        case .decoding(let message):
            return message
        }
    }
}

@MainActor
struct CoachOpenRouterClient {
    var apiKeyProvider: () -> String?

    init(apiKeyProvider: @escaping () -> String? = { OpenRouterCredentialStore.loadAPIKey() }) {
        self.apiKeyProvider = apiKeyProvider
    }

    func chatToolCalling(
        messages: [[String: Any]],
        tools: Data,
        model: String,
        feature: String,
        temperature: Double = 0.2
    ) async throws -> CoachToolCallResponse {
        guard let key = apiKeyProvider(), !key.isEmpty else {
            throw CoachOpenRouterError.missingAPIKey
        }

        let toolsArray: Any
        do {
            toolsArray = try JSONSerialization.jsonObject(with: tools)
        } catch {
            throw CoachOpenRouterError.invalidTools(error.localizedDescription)
        }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WeightTracker", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "tools": toolsArray,
            "tool_choice": "auto",
            "temperature": temperature,
            "metadata": [
                "feature": feature
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachOpenRouterError.invalidResponse("missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(500)) } ?? ""
            throw CoachOpenRouterError.httpStatus(http.statusCode, preview)
        }

        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoachOpenRouterError.decoding("response is not JSON")
        }
        guard
            let choices = top["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(500)) } ?? ""
            throw CoachOpenRouterError.decoding("missing choices[0].message: \(preview)")
        }

        let assistantMessageJSON: Data
        do {
            assistantMessageJSON = try JSONSerialization.data(withJSONObject: message)
        } catch {
            throw CoachOpenRouterError.decoding("could not serialize assistant message: \(error.localizedDescription)")
        }

        var toolCalls: [CoachToolCallResponse.ToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for rawCall in rawCalls {
                guard
                    let id = rawCall["id"] as? String,
                    let function = rawCall["function"] as? [String: Any],
                    let name = function["name"] as? String
                else { continue }

                let argString = (function["arguments"] as? String) ?? "{}"
                let arguments = argString.data(using: .utf8) ?? Data("{}".utf8)
                toolCalls.append(.init(id: id, name: name, arguments: arguments))
            }
        }

        return CoachToolCallResponse(
            assistantMessageJSON: assistantMessageJSON,
            toolCalls: toolCalls
        )
    }
}

struct CoachToolCallResponse {
    struct ToolCall {
        var id: String
        var name: String
        var arguments: Data
    }

    var assistantMessageJSON: Data
    var toolCalls: [ToolCall]
}
