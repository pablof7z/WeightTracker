import Foundation

struct NostrEvent: Codable, Equatable, Hashable, Sendable {
    var id: String
    var pubkey: String
    var created_at: Int
    var kind: Int
    var tags: [[String]]
    var content: String
    var sig: String

    static func computeID(
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String
    ) throws -> (id: String, serializedJSON: Data) {
        let serialized: [Any] = [0, pubkey, createdAt, kind, tags, content]
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: serialized,
                options: [.withoutEscapingSlashes]
            )
        } catch {
            throw NostrError.invalidEvent("could not serialize event id payload: \(error.localizedDescription)")
        }
        return (data.sha256.nostrHex, data)
    }

    static func signed(
        kind: Int,
        content: String,
        tags: [[String]],
        createdAt: Int = Int(Date().timeIntervalSince1970),
        keyPair: NostrKeyPair
    ) throws -> NostrEvent {
        let (id, _) = try computeID(
            pubkey: keyPair.publicKeyHex,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
        guard let idBytes = Data(nostrHex: id) else {
            throw NostrError.invalidEvent("computed id was not hex")
        }
        let signature = try keyPair.signSchnorr(messageDigest: idBytes)
        return NostrEvent(
            id: id,
            pubkey: keyPair.publicKeyHex,
            created_at: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: signature.nostrHex
        )
    }
}

struct NostrFilter: Encodable, Sendable {
    var ids: [String]?
    var authors: [String]?
    var kinds: [Int]?
    var since: Int?
    var until: Int?
    var limit: Int?
    var pTags: [String]?
    var eTags: [String]?
    var aTags: [String]?

    private enum CodingKeys: String, CodingKey {
        case ids
        case authors
        case kinds
        case since
        case until
        case limit
        case pTags = "#p"
        case eTags = "#e"
        case aTags = "#a"
    }
}

extension NostrEvent {
    var eTags: [[String]] {
        tags.filter { $0.first == "e" }
    }

    var aTags: [[String]] {
        tags.filter { $0.first == "a" }
    }

    var pTags: [[String]] {
        tags.filter { $0.first == "p" }
    }

    func conversationRootID() -> String {
        if let rootTag = eTags.first(where: { $0.count >= 4 && $0[3] == "root" }),
           rootTag.count >= 2 {
            return rootTag[1]
        }
        if let firstEventTag = eTags.first, firstEventTag.count >= 2 {
            return firstEventTag[1]
        }
        return id
    }
}
