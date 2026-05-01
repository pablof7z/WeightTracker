import CryptoKit
import Foundation
import P256K

struct NostrKeyPair: Sendable {
    let privateKeyHex: String
    let publicKeyHex: String

    init(privateKeyHex: String, publicKeyHex: String) {
        self.privateKeyHex = privateKeyHex
        self.publicKeyHex = publicKeyHex
    }

    init(privateKeyHex: String) throws {
        let trimmed = privateKeyHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let data = Data(nostrHex: trimmed), data.count == 32 else {
            throw NostrError.invalidPrivateKey
        }
        let key = try P256K.Schnorr.PrivateKey(dataRepresentation: data)
        self.privateKeyHex = trimmed
        self.publicKeyHex = Data(key.xonly.bytes).nostrHex
    }

    init(nsec: String) throws {
        let (hrp, bytes) = try NostrBech32.decode(nsec.trimmingCharacters(in: .whitespacesAndNewlines))
        guard hrp == "nsec", bytes.count == 32 else {
            throw NostrError.invalidPrivateKey
        }
        let key = try P256K.Schnorr.PrivateKey(dataRepresentation: bytes)
        self.privateKeyHex = bytes.nostrHex
        self.publicKeyHex = Data(key.xonly.bytes).nostrHex
    }

    init(secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("nsec1") {
            try self.init(nsec: trimmed)
        } else {
            try self.init(privateKeyHex: trimmed)
        }
    }

    static func generate() throws -> NostrKeyPair {
        let key = try P256K.Schnorr.PrivateKey()
        return NostrKeyPair(
            privateKeyHex: Data(key.dataRepresentation).nostrHex,
            publicKeyHex: Data(key.xonly.bytes).nostrHex
        )
    }

    var nsec: String {
        NostrBech32.encode(hrp: "nsec", bytes: Data(nostrHex: privateKeyHex) ?? Data())
    }

    var npub: String {
        NostrBech32.encode(hrp: "npub", bytes: Data(nostrHex: publicKeyHex) ?? Data())
    }

    func signSchnorr(messageDigest: Data) throws -> Data {
        guard messageDigest.count == 32 else {
            throw NostrError.invalidEvent("Schnorr messages must be 32-byte hashes")
        }
        guard let privateKeyData = Data(nostrHex: privateKeyHex), privateKeyData.count == 32 else {
            throw NostrError.invalidPrivateKey
        }

        let signingKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKeyData)
        var messageBytes = [UInt8](messageDigest)
        var auxiliaryRandomness = [UInt8](repeating: 0, count: 32)
        let signature = try signingKey.signature(message: &messageBytes, auxiliaryRand: &auxiliaryRandomness)
        return Data(signature.dataRepresentation)
    }
}

enum NostrError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidEvent(String)
    case invalidRelayURL(String)
    case relayClosed
    case invalidWireFormat(String)

    var description: String {
        switch self {
        case .invalidPrivateKey:
            return "Invalid Nostr private key"
        case .invalidPublicKey:
            return "Invalid Nostr public key"
        case .invalidEvent(let message):
            return "Invalid Nostr event: \(message)"
        case .invalidRelayURL(let relayURL):
            return "Invalid relay URL: \(relayURL)"
        case .relayClosed:
            return "Relay connection closed"
        case .invalidWireFormat(let message):
            return "Invalid wire format: \(message)"
        }
    }
}

extension Data {
    var sha256: Data {
        Data(SHA256.hash(data: self))
    }
}
