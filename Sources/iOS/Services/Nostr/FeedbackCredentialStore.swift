import Foundation
import Security

enum FeedbackCredentialStore {
    private static let service = "app.pfer.weighttracker.feedback"
    private static let identityAccount = "feedback_identity_nsec"
    private static let bunkerAccount = "feedback_identity_bunker"

    static func loadSecret() -> String? {
        var query = baseQuery(account: identityAccount)
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
        SecItemDelete(baseQuery(account: identityAccount) as CFDictionary)
    }

    static func loadBunkerURI() -> String? {
        loadString(account: bunkerAccount)
    }

    static func saveBunkerURI(_ uri: String) throws {
        try saveString(uri, account: bunkerAccount)
    }

    static func deleteBunkerURI() {
        SecItemDelete(baseQuery(account: bunkerAccount) as CFDictionary)
    }

    private static func loadString(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveNormalizedSecret(_ secret: String) throws {
        try saveString(secret, account: identityAccount)
    }

    private static func saveString(_ value: String, account: String) throws {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        guard let data = value.data(using: .utf8) else {
            throw FeedbackCredentialStoreError.invalidSecretEncoding
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw FeedbackCredentialStoreError.keychainWriteFailed(status)
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

enum FeedbackCredentialStoreError: LocalizedError {
    case invalidSecretEncoding
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidSecretEncoding:
            return "Could not encode the feedback secret for storage."
        case .keychainWriteFailed(let status):
            return "Could not save the feedback identity. Keychain status: \(status)."
        }
    }
}
