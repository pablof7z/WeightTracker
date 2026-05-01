import Foundation
import Security

enum NostrCredentialStore {
    private static let service = "app.pfer.weighttracker.nostr"
    private static let coachAgentAccount = "coach_agent_nsec"

    static func loadSecret() -> String? {
        var query = baseQuery(account: coachAgentAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func loadKeyPair() throws -> NostrKeyPair? {
        guard let secret = loadSecret(), !secret.isEmpty else { return nil }
        return try NostrKeyPair(secret: secret)
    }

    @discardableResult
    static func save(secret: String) throws -> NostrKeyPair {
        let keyPair = try NostrKeyPair(secret: secret)
        try saveNormalizedSecret(keyPair.nsec)
        return keyPair
    }

    @discardableResult
    static func generateAndSave() throws -> NostrKeyPair {
        let keyPair = try NostrKeyPair.generate()
        try saveNormalizedSecret(keyPair.nsec)
        return keyPair
    }

    static func delete() {
        SecItemDelete(baseQuery(account: coachAgentAccount) as CFDictionary)
    }

    private static func saveNormalizedSecret(_ secret: String) throws {
        let query = baseQuery(account: coachAgentAccount)
        SecItemDelete(query as CFDictionary)

        guard let data = secret.data(using: .utf8) else {
            throw NostrCredentialStoreError.invalidSecretEncoding
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NostrCredentialStoreError.keychainWriteFailed(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum NostrCredentialStoreError: LocalizedError {
    case invalidSecretEncoding
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidSecretEncoding:
            return "Could not encode the Nostr secret for storage."
        case .keychainWriteFailed(let status):
            return "Could not save the Nostr secret. Keychain status: \(status)."
        }
    }
}
