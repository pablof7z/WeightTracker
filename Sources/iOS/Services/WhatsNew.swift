import Foundation

struct WhatsNewEntry: Decodable, Sendable, Identifiable, Equatable {
    let shippedAt: Date
    let lines: [String]

    var id: Date { shippedAt }

    private enum CodingKeys: String, CodingKey {
        case shippedAt = "shipped_at"
        case lines
    }
}

private struct WhatsNewPayload: Decodable {
    let schemaVersion: Int
    let entries: [WhatsNewEntry]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entries
    }
}

// Loads the bundled `whats-new.json` and diffs it against a UserDefaults
// timestamp marker to determine which entries the user hasn't seen yet.
//
// First-launch semantics: `seedIfNeeded()` writes the marker = newest entry
// timestamp so new users never see "the entire changelog ever." Entries
// added after their install date surface on future launches.

@MainActor
enum WhatsNewService {

    static let lastSeenAtKey = "whatsNew.lastSeenAt"

    private static let resourceName = "whats-new"
    private static let resourceExtension = "json"

    static func loadEntries(bundle: Bundle = .main) -> [WhatsNewEntry] {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try decode(data)
        } catch {
            return []
        }
    }

    static func decode(_ data: Data) throws -> [WhatsNewEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(WhatsNewPayload.self, from: data)
        return payload.entries
    }

    static var lastSeenAt: Date? {
        guard let s = UserDefaults.standard.string(forKey: lastSeenAtKey),
              !s.isEmpty else {
            return nil
        }
        return iso8601.date(from: s)
    }

    static func markSeen(at date: Date) {
        UserDefaults.standard.set(iso8601.string(from: date), forKey: lastSeenAtKey)
    }

    static func seedIfNeeded(entries: [WhatsNewEntry]? = nil) {
        if UserDefaults.standard.string(forKey: lastSeenAtKey) != nil { return }
        let sorted = (entries ?? loadEntries()).sorted { $0.shippedAt > $1.shippedAt }
        if let newest = sorted.first {
            markSeen(at: newest.shippedAt)
        }
    }

    static func unseenEntries(
        lastSeenAt: Date?,
        entries: [WhatsNewEntry]? = nil
    ) -> [WhatsNewEntry] {
        guard let marker = lastSeenAt else { return [] }
        let all = entries ?? loadEntries()
        return all
            .filter { $0.shippedAt > marker }
            .sorted { $0.shippedAt > $1.shippedAt }
    }

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
