import CryptoKit
import Foundation
import P256K
import Security

enum Nip44Crypto {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidKey
        case invalidPayload
        case unsupportedVersion(UInt8)
        case macMismatch
        case invalidPlaintextLength
        case encryptionFailed
        case decryptionFailed

        var description: String {
            switch self {
            case .invalidKey: return "Invalid secp256k1 key bytes"
            case .invalidPayload: return "Invalid NIP-44 payload"
            case .unsupportedVersion(let version): return String(format: "Unsupported NIP-44 version 0x%02x", version)
            case .macMismatch: return "NIP-44 MAC verification failed"
            case .invalidPlaintextLength: return "NIP-44 plaintext length out of range"
            case .encryptionFailed: return "NIP-44 encryption failed"
            case .decryptionFailed: return "NIP-44 decryption failed"
            }
        }
    }

    private static let salt = Data("nip44-v2".utf8)
    private static let version: UInt8 = 0x02
    private static let nonceSize = 32
    private static let macSize = 32
    private static let minPayloadSize = 99
    private static let maxPlaintextLength = 65_535

    static func encrypt(
        plaintext: String,
        recipientPubKeyHex: String,
        senderPrivKeyHex: String
    ) throws -> String {
        guard let utf8 = plaintext.data(using: .utf8) else { throw Error.encryptionFailed }
        guard !utf8.isEmpty, utf8.count <= maxPlaintextLength else { throw Error.invalidPlaintextLength }

        let convKey = try conversationKey(privHex: senderPrivKeyHex, pubHex: recipientPubKeyHex)

        var nonce = Data(count: nonceSize)
        let status = nonce.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, nonceSize, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw Error.encryptionFailed }

        let keys = messageKeys(conversationKey: convKey, nonce: nonce)
        let padded = paddedPlaintext(utf8)
        let ciphertext = chacha20(key: keys.chachaKey, nonce: keys.chachaNonce, input: padded)
        let mac = hmacSha256(key: keys.hmacKey, data: nonce + ciphertext)

        var payload = Data()
        payload.reserveCapacity(1 + nonceSize + ciphertext.count + macSize)
        payload.append(version)
        payload.append(nonce)
        payload.append(ciphertext)
        payload.append(mac)
        return payload.base64EncodedString()
    }

    static func decrypt(
        payload: String,
        senderPubKeyHex: String,
        recipientPrivKeyHex: String
    ) throws -> String {
        guard let bytes = Data(base64Encoded: payload) else { throw Error.invalidPayload }
        guard bytes.count >= minPayloadSize else { throw Error.invalidPayload }
        guard bytes[bytes.startIndex] == version else {
            throw Error.unsupportedVersion(bytes[bytes.startIndex])
        }

        let nonce = bytes.subdata(in: (bytes.startIndex + 1)..<(bytes.startIndex + 1 + nonceSize))
        let macStart = bytes.endIndex - macSize
        let mac = bytes.subdata(in: macStart..<bytes.endIndex)
        let ciphertext = bytes.subdata(in: (bytes.startIndex + 1 + nonceSize)..<macStart)

        let convKey = try conversationKey(privHex: recipientPrivKeyHex, pubHex: senderPubKeyHex)
        let keys = messageKeys(conversationKey: convKey, nonce: nonce)

        let expectedMac = hmacSha256(key: keys.hmacKey, data: nonce + ciphertext)
        guard constantTimeEquals(mac, expectedMac) else { throw Error.macMismatch }

        let padded = chacha20(key: keys.chachaKey, nonce: keys.chachaNonce, input: ciphertext)
        guard padded.count >= 2 else { throw Error.decryptionFailed }
        let lenHi = Int(padded[padded.startIndex])
        let lenLo = Int(padded[padded.startIndex + 1])
        let plaintextLen = (lenHi << 8) | lenLo
        guard plaintextLen >= 1,
              plaintextLen <= maxPlaintextLength,
              padded.count >= 2 + plaintextLen
        else {
            throw Error.decryptionFailed
        }

        let plaintextData = padded.subdata(in: (padded.startIndex + 2)..<(padded.startIndex + 2 + plaintextLen))
        guard let string = String(data: plaintextData, encoding: .utf8) else { throw Error.decryptionFailed }
        return string
    }

    private static func conversationKey(privHex: String, pubHex: String) throws -> SymmetricKey {
        guard let priv = Data(nostrHex: privHex), priv.count == 32,
              let pubX = Data(nostrHex: pubHex), pubX.count == 32
        else { throw Error.invalidKey }

        let pubCompressed = Data([0x02]) + pubX
        let privKey = try P256K.KeyAgreement.PrivateKey(dataRepresentation: priv)
        let pubKey = try P256K.KeyAgreement.PublicKey(dataRepresentation: pubCompressed, format: .compressed)
        let shared = try privKey.sharedSecretFromKeyAgreement(with: pubKey, format: .compressed)
        let xCoord = shared.withUnsafeBytes { Data($0).dropFirst() }

        let prk = CryptoKit.HKDF<CryptoKit.SHA256>.extract(
            inputKeyMaterial: SymmetricKey(data: xCoord),
            salt: salt
        )
        return SymmetricKey(data: prk)
    }

    private struct MessageKeys {
        let chachaKey: Data
        let chachaNonce: Data
        let hmacKey: Data
    }

    private static func messageKeys(conversationKey: SymmetricKey, nonce: Data) -> MessageKeys {
        let derived = CryptoKit.HKDF<CryptoKit.SHA256>.expand(
            pseudoRandomKey: conversationKey,
            info: nonce,
            outputByteCount: 76
        )
        let bytes = derived.withUnsafeBytes { Data($0) }
        return MessageKeys(
            chachaKey: bytes.subdata(in: bytes.startIndex..<(bytes.startIndex + 32)),
            chachaNonce: bytes.subdata(in: (bytes.startIndex + 32)..<(bytes.startIndex + 44)),
            hmacKey: bytes.subdata(in: (bytes.startIndex + 44)..<(bytes.startIndex + 76))
        )
    }

    private static func hmacSha256(key: Data, data: Data) -> Data {
        let mac = CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
    }

    private static func paddedPlaintext(_ plaintext: Data) -> Data {
        let unpaddedLen = plaintext.count
        let paddedLen = calcPaddedLen(unpaddedLen)
        var output = Data()
        output.reserveCapacity(2 + paddedLen)
        output.append(UInt8((unpaddedLen >> 8) & 0xff))
        output.append(UInt8(unpaddedLen & 0xff))
        output.append(plaintext)
        if paddedLen > unpaddedLen {
            output.append(Data(repeating: 0, count: paddedLen - unpaddedLen))
        }
        return output
    }

    private static func calcPaddedLen(_ len: Int) -> Int {
        if len <= 32 { return 32 }
        let nextPower = 1 << (Int.bitWidth - (len - 1).leadingZeroBitCount)
        let chunk = nextPower <= 256 ? 32 : nextPower / 8
        return chunk * (((len - 1) / chunk) + 1)
    }

    private static func chacha20(key: Data, nonce: Data, input: Data) -> Data {
        precondition(key.count == 32 && nonce.count == 12, "ChaCha20 requires 32-byte key and 12-byte nonce")

        var state = [UInt32](repeating: 0, count: 16)
        state[0] = 0x6170_7865
        state[1] = 0x3320_646e
        state[2] = 0x7962_2d32
        state[3] = 0x6b20_6574
        for i in 0..<8 { state[4 + i] = leU32(key, offset: i * 4) }
        state[12] = 0
        for i in 0..<3 { state[13 + i] = leU32(nonce, offset: i * 4) }

        var output = Data()
        output.reserveCapacity(input.count)
        var processed = 0
        let inputBytes = [UInt8](input)
        while processed < input.count {
            let block = chachaBlock(state: state)
            let chunk = min(64, input.count - processed)
            for i in 0..<chunk {
                output.append(inputBytes[processed + i] ^ block[i])
            }
            processed += chunk
            state[12] = state[12] &+ 1
        }
        return output
    }

    private static func chachaBlock(state: [UInt32]) -> [UInt8] {
        var working = state
        for _ in 0..<10 {
            quarterRound(&working, 0, 4, 8, 12)
            quarterRound(&working, 1, 5, 9, 13)
            quarterRound(&working, 2, 6, 10, 14)
            quarterRound(&working, 3, 7, 11, 15)
            quarterRound(&working, 0, 5, 10, 15)
            quarterRound(&working, 1, 6, 11, 12)
            quarterRound(&working, 2, 7, 8, 13)
            quarterRound(&working, 3, 4, 9, 14)
        }

        var output = [UInt8](repeating: 0, count: 64)
        for i in 0..<16 {
            let value = working[i] &+ state[i]
            output[i * 4 + 0] = UInt8(truncatingIfNeeded: value)
            output[i * 4 + 1] = UInt8(truncatingIfNeeded: value >> 8)
            output[i * 4 + 2] = UInt8(truncatingIfNeeded: value >> 16)
            output[i * 4 + 3] = UInt8(truncatingIfNeeded: value >> 24)
        }
        return output
    }

    private static func quarterRound(_ w: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        w[a] = w[a] &+ w[b]; w[d] ^= w[a]; w[d] = rotl(w[d], 16)
        w[c] = w[c] &+ w[d]; w[b] ^= w[c]; w[b] = rotl(w[b], 12)
        w[a] = w[a] &+ w[b]; w[d] ^= w[a]; w[d] = rotl(w[d], 8)
        w[c] = w[c] &+ w[d]; w[b] ^= w[c]; w[b] = rotl(w[b], 7)
    }

    @inline(__always)
    private static func rotl(_ value: UInt32, _ shift: UInt32) -> UInt32 {
        (value << shift) | (value >> (32 &- shift))
    }

    @inline(__always)
    private static func leU32(_ data: Data, offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i])
            | (UInt32(data[i + 1]) << 8)
            | (UInt32(data[i + 2]) << 16)
            | (UInt32(data[i + 3]) << 24)
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<lhs.count {
            diff |= lhs[lhs.startIndex + i] ^ rhs[rhs.startIndex + i]
        }
        return diff == 0
    }
}
