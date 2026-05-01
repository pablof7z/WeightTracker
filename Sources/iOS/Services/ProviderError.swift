import Foundation

enum ProviderError: LocalizedError {
    case missingKey(provider: String)
    case http(status: Int, body: String)
    case decoding(String)
    case network(String)
    case audio(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            return "Missing API key for \(provider). Open Settings to add one."
        case .http(let status, let body):
            return "HTTP \(status): \(body.prefix(240))"
        case .decoding(let detail):
            return "Could not decode provider response: \(detail)"
        case .network(let detail):
            return "Network error: \(detail)"
        case .audio(let detail):
            return "Audio error: \(detail)"
        case .invalidResponse:
            return "Invalid response from provider."
        }
    }
}
