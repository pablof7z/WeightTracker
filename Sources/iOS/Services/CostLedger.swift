import Combine
import Foundation

enum CostFeature {
    static let coachAgentRun = "coach.agent.run"

    static func displayName(for feature: String) -> String {
        switch feature {
        case coachAgentRun: return "Coach agent"
        default: return feature
        }
    }
}

struct UsageRecord: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var at: Date
    var feature: String
    var model: String
    var promptTokens: Int
    var completionTokens: Int
    var cachedTokens: Int
    var reasoningTokens: Int
    var costUSD: Double
    var latencyMs: Int
}

struct OpenRouterUsagePayload: Decodable, Sendable {
    struct PromptDetails: Decodable, Sendable {
        let cached_tokens: Int?
        let cache_write_tokens: Int?
        let audio_tokens: Int?
    }

    struct CompletionDetails: Decodable, Sendable {
        let reasoning_tokens: Int?
    }

    let prompt_tokens: Int?
    let completion_tokens: Int?
    let total_tokens: Int?
    let cost: Double?
    let prompt_tokens_details: PromptDetails?
    let completion_tokens_details: CompletionDetails?
}

@MainActor
final class CostLedger: ObservableObject {
    static let shared = CostLedger()

    @Published private(set) var records: [UsageRecord]

    private let directoryURL: URL
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directoryURL = base.appendingPathComponent("UsageLedger", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("ledger.json")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        records = Self.load(from: fileURL)
    }

    func log(
        feature: String,
        model: String,
        usage: OpenRouterUsagePayload?,
        latencyMs: Int
    ) {
        let record = UsageRecord(
            id: UUID(),
            at: Date(),
            feature: feature,
            model: model,
            promptTokens: usage?.prompt_tokens ?? 0,
            completionTokens: usage?.completion_tokens ?? 0,
            cachedTokens: usage?.prompt_tokens_details?.cached_tokens ?? 0,
            reasoningTokens: usage?.completion_tokens_details?.reasoning_tokens ?? 0,
            costUSD: usage?.cost ?? 0,
            latencyMs: latencyMs
        )
        records.insert(record, at: 0)
        save()
    }

    func clear() {
        records = []
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageRecord].self, from: data)) ?? []
    }
}
