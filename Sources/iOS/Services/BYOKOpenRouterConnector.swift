import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct OpenRouterConnection: Equatable {
    let keyID: String
    let keyLabel: String
    let connectedAt: Date
}

struct BYOKProviderConnection: Equatable {
    let provider: String
    let apiKey: String
    let keyID: String
    let keyLabel: String
    let connectedAt: Date
}

enum OpenRouterCredentialStore {
    private static let service = "app.pfer.weighttracker.openrouter"
    private static let account = "byok"

    static func loadConnection() -> OpenRouterConnection? {
        guard let credential = loadCredential() else { return nil }
        return OpenRouterConnection(
            keyID: credential.keyID,
            keyLabel: credential.keyLabel,
            connectedAt: credential.connectedAt
        )
    }

    static func loadAPIKey() -> String? {
        loadCredential()?.apiKey
    }

    static func save(apiKey: String, keyID: String, keyLabel: String) throws -> OpenRouterConnection {
        let credential = StoredOpenRouterCredential(
            apiKey: apiKey,
            keyID: keyID,
            keyLabel: keyLabel.isEmpty ? "Default" : keyLabel,
            connectedAt: Date()
        )
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw BYOKProviderError.keychainWriteFailed("OpenRouter", status) }

        return OpenRouterConnection(
            keyID: credential.keyID,
            keyLabel: credential.keyLabel,
            connectedAt: credential.connectedAt
        )
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadCredential() -> StoredOpenRouterCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredOpenRouterCredential.self, from: data)
    }
}

@MainActor
final class BYOKProviderConnector: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let byokOrigin = URL(string: "https://byok.f7z.io")!
    private static let clientID = "app.pfer.weighttracker"
    private static let appName = "WeightTracker"
    private static let callbackScheme = "weighttracker"
    private static let redirectURI = "weighttracker://byok"

    private var session: ASWebAuthenticationSession?

    func connect(provider: String) async throws -> BYOKProviderConnection {
        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProvider.isEmpty else { throw BYOKProviderError.invalidProvider }

        let verifier = Self.randomBase64URL(byteCount: 32)
        let state = Self.randomBase64URL(byteCount: 24)
        let callbackURL = try await authenticate(
            url: Self.authorizationURL(provider: normalizedProvider, verifier: verifier, state: state)
        )
        let code = try Self.authorizationCode(from: callbackURL, expectedState: state)
        let token = try await Self.exchange(code: code, verifier: verifier, expectedProvider: normalizedProvider)
        return BYOKProviderConnection(
            provider: token.provider,
            apiKey: token.apiKey,
            keyID: token.keyID,
            keyLabel: token.keyLabel.isEmpty ? "Default" : token.keyLabel,
            connectedAt: Date()
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            if let window = scene.windows.first(where: \.isKeyWindow) {
                return window
            }
        }
        return ASPresentationAnchor()
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error {
                        continuation.resume(throwing: Self.mapAuthenticationError(error))
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: BYOKProviderError.missingCallback)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            if !session.start() {
                self.session = nil
                continuation.resume(throwing: BYOKProviderError.couldNotStart)
            }
        }
    }

    private static func authorizationURL(provider: String, verifier: String, state: String) -> URL {
        var components = URLComponents(url: byokOrigin.appending(path: "authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "app_name", value: appName),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "key:\(provider)"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components.url!
    }

    private static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = params["error"], !error.isEmpty {
            throw BYOKProviderError.accessDenied(error)
        }
        guard params["state"] == expectedState else {
            throw BYOKProviderError.stateMismatch
        }
        guard let code = params["code"], !code.isEmpty else {
            throw BYOKProviderError.missingCode
        }
        return code
    }

    private static func exchange(code: String, verifier: String, expectedProvider: String) async throws -> BYOKTokenResponse {
        let tokenURL = byokOrigin.appending(path: "api/token")
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(BYOKTokenRequest(
            code: code,
            codeVerifier: verifier,
            clientID: clientID,
            redirectURI: redirectURI
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BYOKProviderError.invalidTokenResponse(expectedProvider)
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = (try? JSONDecoder().decode(BYOKErrorResponse.self, from: data).error) ?? "token_exchange_failed"
            throw BYOKProviderError.tokenExchangeFailed(error)
        }
        let token = try JSONDecoder().decode(BYOKTokenResponse.self, from: data)
        guard token.provider.lowercased() == expectedProvider, !token.apiKey.isEmpty else {
            throw BYOKProviderError.invalidTokenResponse(expectedProvider)
        }
        return token
    }

    private static func mapAuthenticationError(_ error: Error) -> Error {
        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            return BYOKProviderError.cancelled
        }
        return error
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Unable to generate secure random bytes")
        return Data(bytes).base64URLEncodedString()
    }
}

@MainActor
final class BYOKOpenRouterConnector {
    private let connector = BYOKProviderConnector()

    func connect() async throws -> OpenRouterConnection {
        let token = try await connector.connect(provider: "openrouter")
        return try OpenRouterCredentialStore.save(
            apiKey: token.apiKey,
            keyID: token.keyID,
            keyLabel: token.keyLabel
        )
    }
}

@MainActor
final class BYOKElevenLabsConnector {
    private let connector = BYOKProviderConnector()

    func connect() async throws -> ElevenLabsConnection {
        let token = try await connector.connect(provider: "elevenlabs")
        return try ElevenLabsCredentialStore.save(
            apiKey: token.apiKey,
            keyID: token.keyID,
            keyLabel: token.keyLabel
        )
    }
}

private struct StoredOpenRouterCredential: Codable {
    let apiKey: String
    let keyID: String
    let keyLabel: String
    let connectedAt: Date
}

private struct BYOKTokenRequest: Encodable {
    let grantType = "authorization_code"
    let code: String
    let codeVerifier: String
    let clientID: String
    let redirectURI: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case code
        case codeVerifier = "code_verifier"
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
    }
}

private struct BYOKTokenResponse: Decodable {
    let provider: String
    let apiKey: String
    let keyID: String
    let keyLabel: String

    enum CodingKeys: String, CodingKey {
        case provider
        case apiKey = "api_key"
        case keyID = "key_id"
        case keyLabel = "key_label"
    }
}

private struct BYOKErrorResponse: Decodable {
    let error: String
}

private enum BYOKProviderError: LocalizedError {
    case accessDenied(String)
    case cancelled
    case couldNotStart
    case invalidProvider
    case invalidTokenResponse(String)
    case keychainWriteFailed(String, OSStatus)
    case missingCallback
    case missingCode
    case stateMismatch
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access was denied in BYOK."
        case .cancelled:
            return "BYOK connection was cancelled."
        case .couldNotStart:
            return "Could not open BYOK."
        case .invalidProvider:
            return "BYOK provider is missing."
        case .invalidTokenResponse(let provider):
            return "BYOK returned an invalid \(provider) token response."
        case .keychainWriteFailed(let provider, let status):
            return "Could not save the \(provider) key to Keychain (\(status))."
        case .missingCallback:
            return "BYOK did not return to the app."
        case .missingCode:
            return "BYOK did not return an authorization code."
        case .stateMismatch:
            return "BYOK returned an authorization response with an invalid state."
        case .tokenExchangeFailed(let reason):
            return "BYOK token exchange failed: \(reason)."
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
