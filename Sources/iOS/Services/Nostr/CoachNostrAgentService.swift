import Foundation
import SwiftUI

struct CoachNostrAgentSettings: Equatable, Sendable {
    var enabled: Bool
    var relayURL: String
    var since: Int?

    static let enabledKey = "nostr.coach.enabled"
    static let relayURLKey = "nostr.coach.relayURL"
    static let sinceKey = "nostr.coach.since"
    static let defaultRelayURL = "wss://relay.damus.io"

    static func load(defaults: UserDefaults = .standard) -> CoachNostrAgentSettings {
        let relayURL = defaults.string(forKey: relayURLKey) ?? defaultRelayURL
        let since = defaults.object(forKey: sinceKey) as? Int
        return CoachNostrAgentSettings(
            enabled: defaults.bool(forKey: enabledKey),
            relayURL: relayURL,
            since: since
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Self.enabledKey)
        defaults.set(relayURL, forKey: Self.relayURLKey)
        if let since {
            defaults.set(since, forKey: Self.sinceKey)
        } else {
            defaults.removeObject(forKey: Self.sinceKey)
        }
    }
}

@MainActor
final class CoachNostrAgentService: ObservableObject {
    enum Status: Equatable {
        case idle
        case missingCredentials
        case starting
        case running(relayURL: String)
        case backingOff(error: String)
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var publicKeyHex: String?
    @Published private(set) var publicKeyNpub: String?
    @Published private(set) var lastMention: NostrEvent?

    var onKind1Mention: ((NostrEvent) async -> Void)?

    private let mentionSubscriptionID = "coach-kind1-mentions"
    private var relay: NostrRelay?
    private var listenerTask: Task<Void, Never>?
    private var settings = CoachNostrAgentSettings.load()

    func start(settings: CoachNostrAgentSettings = .load()) {
        self.settings = settings
        stop()

        guard settings.enabled else {
            status = .idle
            return
        }

        let keyPair: NostrKeyPair
        do {
            guard let stored = try NostrCredentialStore.loadKeyPair() else {
                status = .missingCredentials
                return
            }
            keyPair = stored
        } catch {
            status = .error(String(describing: error))
            return
        }

        guard let url = URL(string: settings.relayURL),
              url.scheme == "ws" || url.scheme == "wss" else {
            status = .error("Invalid relay URL: \(settings.relayURL)")
            return
        }

        publicKeyHex = keyPair.publicKeyHex
        publicKeyNpub = keyPair.npub

        let relay = NostrRelay(url: url)
        self.relay = relay
        status = .starting

        listenerTask = Task { [weak self, keyPair, settings] in
            await relay.setAuthSigner { relayURL, challenge in
                let tags = [["relay", relayURL], ["challenge", challenge]]
                return try? NostrEvent.signed(kind: 22242, content: "", tags: tags, keyPair: keyPair)
            }
            await self?.runMentionLoop(relay: relay, keyPair: keyPair, settings: settings)
        }
    }

    func stop() {
        listenerTask?.cancel()
        listenerTask = nil
        if let relay {
            Task { await relay.stop() }
        }
        relay = nil
        status = .idle
    }

    func restart() {
        start(settings: settings)
    }

    func sign(kind: Int, content: String, tags: [[String]]) async throws -> NostrEvent {
        guard let keyPair = try NostrCredentialStore.loadKeyPair() else {
            throw CoachNostrAgentError.missingCredentials
        }
        return try NostrEvent.signed(kind: kind, content: content, tags: tags, keyPair: keyPair)
    }

    @discardableResult
    func publishKind1(
        content: String,
        pTags: [String],
        additionalTags: [[String]] = []
    ) async throws -> NostrEvent {
        guard let relay else { throw CoachNostrAgentError.notConnected }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NostrError.invalidEvent("kind:1 content is empty")
        }

        var tags = additionalTags
        for pubkey in Self.uniquePubkeys(pTags) {
            tags.append(["p", pubkey])
        }

        let event = try await sign(kind: 1, content: trimmed, tags: tags)
        try await relay.publishAndAwaitOK(event)
        return event
    }

    @discardableResult
    func reply(
        to parent: NostrEvent,
        content: String,
        threadEvents: [NostrEvent] = []
    ) async throws -> NostrEvent {
        let tags = Self.replyTags(
            to: parent,
            threadEvents: threadEvents,
            excludingPubkey: publicKeyHex
        )
        return try await publishKind1(content: content, pTags: [], additionalTags: tags)
    }

    func fetchThread(for event: NostrEvent, timeoutSeconds: Double = 4) async -> [NostrEvent] {
        guard let relay else { return [] }
        let rootID = event.conversationRootID()
        async let root = relay.fetch(filter: NostrFilter(ids: [rootID]), timeoutSeconds: timeoutSeconds)
        async let replies = relay.fetch(filter: NostrFilter(kinds: [1], eTags: [rootID]), timeoutSeconds: timeoutSeconds)
        let combined = await root + replies
        var seen = Set<String>()
        return combined
            .sorted { $0.created_at < $1.created_at }
            .filter { seen.insert($0.id).inserted }
    }

    static func replyTags(
        to parent: NostrEvent,
        threadEvents: [NostrEvent],
        excludingPubkey: String? = nil
    ) -> [[String]] {
        let rootID = parent.conversationRootID()
        let rootEvent = threadEvents.first(where: { $0.id == rootID }) ?? parent

        var tags: [[String]] = rootEvent.aTags
        tags.append(["e", rootID, "", "root"])
        if parent.id != rootID {
            tags.append(["e", parent.id, "", "reply"])
        }

        let participantEvents = ([rootEvent, parent] + threadEvents)
        var pTagCandidates: [String] = participantEvents.map(\.pubkey)
        pTagCandidates.append(contentsOf: participantEvents.flatMap { event in
            event.pTags.compactMap { $0.count >= 2 ? $0[1] : nil }
        })

        for pubkey in uniquePubkeys(pTagCandidates) where pubkey != excludingPubkey {
            tags.append(["p", pubkey])
        }
        return tags
    }

    private func runMentionLoop(
        relay: NostrRelay,
        keyPair: NostrKeyPair,
        settings: CoachNostrAgentSettings
    ) async {
        let stream = await relay.events()
        let filter = NostrFilter(kinds: [1], since: settings.since, pTags: [keyPair.publicKeyHex])
        await relay.subscribe(id: mentionSubscriptionID, filter: filter)

        for await frame in stream {
            switch frame {
            case .connected:
                status = .running(relayURL: relay.displayURL)
            case .disconnected(let error):
                status = .backingOff(error: error ?? "Disconnected")
            case .event(let subscriptionID, let event):
                guard subscriptionID == mentionSubscriptionID, event.kind == 1 else { continue }
                lastMention = event
                UserDefaults.standard.set(event.created_at, forKey: CoachNostrAgentSettings.sinceKey)
                await onKind1Mention?(event)
            case .eose, .ok, .notice, .auth:
                continue
            }
        }
    }

    private static func uniquePubkeys(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { pubkey in
                guard pubkey.count == 64, Data(nostrHex: pubkey) != nil else { return false }
                return seen.insert(pubkey).inserted
            }
    }
}

enum CoachNostrAgentError: LocalizedError {
    case missingCredentials
    case notConnected

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "No Nostr coach agent key is stored."
        case .notConnected:
            return "Nostr relay is not connected."
        }
    }
}
