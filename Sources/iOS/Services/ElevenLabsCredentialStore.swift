import Foundation
import Security

struct ElevenLabsConnection: Equatable {
    let keyID: String
    let keyLabel: String
    let connectedAt: Date
}

enum ElevenLabsCredentialStore {
    private static let service = "app.pfer.weighttracker.elevenlabs"
    private static let account = "api-key"

    static func loadConnection() -> ElevenLabsConnection? {
        guard let credential = loadCredential() else { return nil }
        return ElevenLabsConnection(
            keyID: credential.keyID,
            keyLabel: credential.keyLabel,
            connectedAt: credential.connectedAt
        )
    }

    static func loadAPIKey() -> String? {
        if let credential = loadCredential() {
            return credential.apiKey
        }
        return loadLegacyAPIKey()
    }

    static func save(apiKey: String, keyID: String, keyLabel: String) throws -> ElevenLabsConnection {
        let credential = StoredElevenLabsCredential(
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
        guard status == errSecSuccess else { throw ElevenLabsCredentialStoreError.keychainWriteFailed(status) }

        return ElevenLabsConnection(
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

    private static func loadCredential() -> StoredElevenLabsCredential? {
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
        return try? JSONDecoder().decode(StoredElevenLabsCredential.self, from: data)
    }

    private static func loadLegacyAPIKey() -> String? {
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
        return String(data: data, encoding: .utf8)
    }
}

private struct StoredElevenLabsCredential: Codable {
    let apiKey: String
    let keyID: String
    let keyLabel: String
    let connectedAt: Date
}

private enum ElevenLabsCredentialStoreError: LocalizedError {
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let status):
            return "Could not save the ElevenLabs key to Keychain (\(status))."
        }
    }
}
