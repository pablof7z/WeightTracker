import Foundation
import SwiftUI

struct CoachAgentMemory: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var text: String
    var source: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, source: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.source = source
        self.createdAt = createdAt
    }
}

enum NostrConversationDirection: String, Codable, Sendable {
    case incoming
    case outgoing
}

struct NostrConversationTurn: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var eventID: String
    var pubkey: String
    var direction: NostrConversationDirection
    var content: String
    var createdAt: Int

    init(
        id: UUID = UUID(),
        eventID: String,
        pubkey: String,
        direction: NostrConversationDirection,
        content: String,
        createdAt: Int
    ) {
        self.id = id
        self.eventID = eventID
        self.pubkey = pubkey
        self.direction = direction
        self.content = content
        self.createdAt = createdAt
    }
}

struct NostrConversation: Identifiable, Codable, Equatable, Sendable {
    var rootEventID: String
    var counterpartyPubkey: String
    var firstSeen: Date
    var lastTouched: Date
    var turns: [NostrConversationTurn]

    var id: String { rootEventID }
}

struct NostrPendingApproval: Identifiable, Codable, Equatable, Sendable {
    var eventID: String
    var senderPubkey: String
    var content: String
    var createdAt: Int
    var queuedAt: Date
    var rootEventID: String
    var eventJSON: String

    var id: String { eventID }
}

struct CoachNostrAgentState: Codable, Equatable, Sendable {
    var respondedEventIDs: Set<String>
    var allowedPubkeys: Set<String>
    var blockedPubkeys: Set<String>
    var pendingApprovals: [NostrPendingApproval]
    var conversations: [NostrConversation]
    var memories: [CoachAgentMemory]
    var publicKeyHex: String?

    static let empty = CoachNostrAgentState(
        respondedEventIDs: [],
        allowedPubkeys: [],
        blockedPubkeys: [],
        pendingApprovals: [],
        conversations: [],
        memories: [],
        publicKeyHex: nil
    )

    static func load(defaults: UserDefaults = .standard) -> CoachNostrAgentState {
        guard let data = defaults.data(forKey: AppPrefKey.agentNostrState),
              let state = try? JSONDecoder().decode(CoachNostrAgentState.self, from: data) else {
            return .empty
        }
        return state
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppPrefKey.agentNostrState)
    }
}

struct CoachNostrAgentSettings: Equatable, Sendable {
    var enabled: Bool
    var relayURL: String
    var profileName: String
    var profileAbout: String
    var systemPrompt: String
    var since: Int?

    static let enabledKey = AppPrefKey.agentNostrEnabled
    static let relayURLKey = AppPrefKey.agentNostrRelayURL
    static let sinceKey = AppPrefKey.agentNostrSince
    static let profileNameKey = AppPrefKey.agentNostrProfileName
    static let profileAboutKey = AppPrefKey.agentNostrProfileAbout
    static let systemPromptKey = AppPrefKey.agentSystemPrompt

    private static let legacyEnabledKey = "nostr.coach.enabled"
    private static let legacyRelayURLKey = "nostr.coach.relayURL"
    private static let legacySinceKey = "nostr.coach.since"

    static let defaultRelayURL = "wss://relay.tenex.chat"
    static let defaultProfileName = "WeightTracker Agent"
    static let defaultProfileAbout = "A local weight-cut coach agent."
    static let defaultSystemPrompt = """
    Be factual and terse.
    Do not use encouragement, praise, pep talk, moral judgment, streak language, or filler.
    When data is missing, ask for the smallest useful missing detail.
    """

    static func load(defaults: UserDefaults = .standard) -> CoachNostrAgentSettings {
        let enabled = (defaults.object(forKey: enabledKey) as? Bool)
            ?? (defaults.object(forKey: legacyEnabledKey) as? Bool)
            ?? false
        let relayURL = defaults.string(forKey: relayURLKey)
            ?? defaults.string(forKey: legacyRelayURLKey)
            ?? defaultRelayURL
        let since = (defaults.object(forKey: sinceKey) as? Int)
            ?? (defaults.object(forKey: legacySinceKey) as? Int)
        return CoachNostrAgentSettings(
            enabled: enabled,
            relayURL: relayURL,
            profileName: defaults.string(forKey: profileNameKey) ?? defaultProfileName,
            profileAbout: defaults.string(forKey: profileAboutKey) ?? defaultProfileAbout,
            systemPrompt: defaults.string(forKey: systemPromptKey) ?? defaultSystemPrompt,
            since: since
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Self.enabledKey)
        defaults.set(relayURL, forKey: Self.relayURLKey)
        defaults.set(profileName, forKey: Self.profileNameKey)
        defaults.set(profileAbout, forKey: Self.profileAboutKey)
        defaults.set(systemPrompt, forKey: Self.systemPromptKey)
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
    @Published private(set) var state: CoachNostrAgentState

    var onKind1Mention: ((NostrEvent) async -> Void)?

    private let defaults: UserDefaults
    private let mentionSubscriptionID = "coach-kind1-mentions"
    private var relay: NostrRelay?
    private var listenerTask: Task<Void, Never>?
    private var settings: CoachNostrAgentSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.state = CoachNostrAgentState.load(defaults: defaults)
        self.settings = CoachNostrAgentSettings.load(defaults: defaults)
        self.publicKeyHex = state.publicKeyHex
        self.publicKeyNpub = state.publicKeyHex.map(Self.npub)
    }

    func start(settings: CoachNostrAgentSettings = .load()) {
        self.settings = settings
        stop()

        guard settings.enabled else {
            status = .idle
            return
        }

        do {
            let keyPair = try loadOrCreateKeyPair()

            guard let url = URL(string: settings.relayURL),
                  url.scheme == "ws" || url.scheme == "wss" else {
                status = .error("Invalid relay URL: \(settings.relayURL)")
                return
            }

            publicKeyHex = keyPair.publicKeyHex
            publicKeyNpub = keyPair.npub
            updateState { state in
                state.publicKeyHex = keyPair.publicKeyHex
            }

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
        } catch {
            status = .error(String(describing: error))
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

    func ensureIdentity() {
        do {
            let keyPair = try loadOrCreateKeyPair()
            publicKeyHex = keyPair.publicKeyHex
            publicKeyNpub = keyPair.npub
            updateState { state in
                state.publicKeyHex = keyPair.publicKeyHex
            }
        } catch {
            status = .error(String(describing: error))
        }
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
        let event = try await publishKind1(content: content, pTags: [], additionalTags: tags)
        recordOutgoingReply(event, parent: parent)
        return event
    }

    @discardableResult
    func recordMemory(text: String, source: String = "agent") throws -> CoachAgentMemory {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CoachNostrAgentError.invalidMemory }
        let memory = CoachAgentMemory(text: String(trimmed.prefix(1_000)), source: source)
        updateState { state in
            state.memories.insert(memory, at: 0)
            if state.memories.count > 200 {
                state.memories.removeLast(state.memories.count - 200)
            }
        }
        return memory
    }

    func deleteMemory(_ id: UUID) {
        updateState { state in
            state.memories.removeAll { $0.id == id }
        }
    }

    func allow(pubkey: String) async {
        let normalized = (try? Self.normalizedPubkey(pubkey)) ?? pubkey
        updateState { state in
            state.allowedPubkeys.insert(normalized)
            state.blockedPubkeys.remove(normalized)
        }
        await drainPendingApprovals(for: normalized)
    }

    func block(pubkey: String) {
        let normalized = (try? Self.normalizedPubkey(pubkey)) ?? pubkey
        let pendingIDs = state.pendingApprovals
            .filter { $0.senderPubkey == normalized }
            .map(\.eventID)
        updateState { state in
            state.blockedPubkeys.insert(normalized)
            state.allowedPubkeys.remove(normalized)
            state.respondedEventIDs.formUnion(pendingIDs)
            state.pendingApprovals.removeAll { $0.senderPubkey == normalized }
        }
    }

    func revoke(pubkey: String) {
        let normalized = (try? Self.normalizedPubkey(pubkey)) ?? pubkey
        updateState { state in
            state.allowedPubkeys.remove(normalized)
        }
    }

    func unblock(pubkey: String) {
        let normalized = (try? Self.normalizedPubkey(pubkey)) ?? pubkey
        updateState { state in
            state.blockedPubkeys.remove(normalized)
        }
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

    static func normalizedPubkey(_ value: String) throws -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("nostr:") {
            trimmed.removeFirst("nostr:".count)
        }

        if trimmed.hasPrefix("npub1") {
            let decoded = try NostrBech32.decode(trimmed)
            guard decoded.hrp == "npub", decoded.bytes.count == 32 else {
                throw CoachNostrAgentError.invalidPubkey
            }
            return decoded.bytes.nostrHex
        }

        guard trimmed.count == 64, Data(nostrHex: trimmed)?.count == 32 else {
            throw CoachNostrAgentError.invalidPubkey
        }
        return trimmed
    }

    static func npub(_ pubkey: String) -> String {
        NostrBech32.encode(hrp: "npub", bytes: Data(nostrHex: pubkey) ?? Data())
    }

    static func shortNpub(_ pubkey: String) -> String {
        let npub = npub(pubkey)
        guard npub.count > 16 else { return npub }
        return "\(npub.prefix(10))...\(npub.suffix(6))"
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
                await publishProfile(relay: relay, keyPair: keyPair, settings: settings)
            case .disconnected(let error):
                status = .backingOff(error: error ?? "Disconnected")
            case .event(let subscriptionID, let event):
                guard subscriptionID == mentionSubscriptionID, event.kind == 1 else { continue }
                await handleInbound(event, agentPubkey: keyPair.publicKeyHex)
            case .eose, .ok, .notice, .auth:
                continue
            }
        }
    }

    private func handleInbound(_ event: NostrEvent, agentPubkey: String?) async {
        guard event.kind == 1 else { return }
        guard event.pubkey != agentPubkey else {
            markResponded(event.id)
            return
        }
        guard !state.respondedEventIDs.contains(event.id) else { return }

        saveSince(event.created_at)

        if state.blockedPubkeys.contains(event.pubkey) {
            markResponded(event.id)
            return
        }

        guard state.allowedPubkeys.contains(event.pubkey) else {
            enqueuePendingApproval(event)
            return
        }

        lastMention = event
        recordIncoming(event)
        markResponded(event.id)
        await onKind1Mention?(event)
    }

    private func drainPendingApprovals(for pubkey: String) async {
        let queued = state.pendingApprovals
            .filter { $0.senderPubkey == pubkey }
            .sorted { $0.createdAt < $1.createdAt }
        guard !queued.isEmpty else { return }

        updateState { state in
            state.pendingApprovals.removeAll { $0.senderPubkey == pubkey }
        }

        for approval in queued {
            guard let data = approval.eventJSON.data(using: .utf8),
                  let event = try? JSONDecoder().decode(NostrEvent.self, from: data) else {
                markResponded(approval.eventID)
                continue
            }
            await handleInbound(event, agentPubkey: publicKeyHex ?? state.publicKeyHex)
        }
    }

    private func enqueuePendingApproval(_ event: NostrEvent) {
        guard !state.pendingApprovals.contains(where: { $0.eventID == event.id }) else { return }
        guard let data = try? JSONEncoder().encode(event),
              let eventJSON = String(data: data, encoding: .utf8) else { return }
        let approval = NostrPendingApproval(
            eventID: event.id,
            senderPubkey: event.pubkey,
            content: event.content,
            createdAt: event.created_at,
            queuedAt: Date(),
            rootEventID: event.conversationRootID(),
            eventJSON: eventJSON
        )
        updateState { state in
            state.pendingApprovals.append(approval)
            state.pendingApprovals.sort { $0.createdAt < $1.createdAt }
        }
    }

    private func publishProfile(
        relay: NostrRelay,
        keyPair: NostrKeyPair,
        settings: CoachNostrAgentSettings
    ) async {
        let name = settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CoachNostrAgentSettings.defaultProfileName
            : settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let about = settings.profileAbout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CoachNostrAgentSettings.defaultProfileAbout
            : settings.profileAbout.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = [
            "name": name,
            "display_name": name,
            "about": about
        ]

        guard
            let data = try? JSONSerialization.data(
                withJSONObject: metadata,
                options: [.sortedKeys, .withoutEscapingSlashes]
            ),
            let content = String(data: data, encoding: .utf8),
            let event = try? NostrEvent.signed(kind: 0, content: content, tags: [], keyPair: keyPair)
        else { return }

        try? await relay.publishAndAwaitOK(event, timeout: 3)
    }

    private func saveSince(_ createdAt: Int) {
        let current = defaults.object(forKey: CoachNostrAgentSettings.sinceKey) as? Int
        guard current == nil || createdAt > current! else { return }
        defaults.set(createdAt, forKey: CoachNostrAgentSettings.sinceKey)
        settings.since = createdAt
    }

    private func markResponded(_ eventID: String) {
        updateState { state in
            state.respondedEventIDs.insert(eventID)
            if state.respondedEventIDs.count > 500 {
                state.respondedEventIDs = Set(state.respondedEventIDs.prefix(500))
            }
        }
    }

    private func recordIncoming(_ event: NostrEvent) {
        recordConversationTurn(
            rootEventID: event.conversationRootID(),
            counterpartyPubkey: event.pubkey,
            turn: NostrConversationTurn(
                eventID: event.id,
                pubkey: event.pubkey,
                direction: .incoming,
                content: event.content,
                createdAt: event.created_at
            )
        )
    }

    private func recordOutgoingReply(_ event: NostrEvent, parent: NostrEvent) {
        recordConversationTurn(
            rootEventID: parent.conversationRootID(),
            counterpartyPubkey: parent.pubkey,
            turn: NostrConversationTurn(
                eventID: event.id,
                pubkey: event.pubkey,
                direction: .outgoing,
                content: event.content,
                createdAt: event.created_at
            )
        )
    }

    private func recordConversationTurn(
        rootEventID: String,
        counterpartyPubkey: String,
        turn: NostrConversationTurn
    ) {
        updateState { state in
            let touched = Date(timeIntervalSince1970: TimeInterval(turn.createdAt))
            if let index = state.conversations.firstIndex(where: { $0.rootEventID == rootEventID }) {
                guard !state.conversations[index].turns.contains(where: { $0.eventID == turn.eventID && $0.direction == turn.direction }) else {
                    return
                }
                state.conversations[index].turns.append(turn)
                state.conversations[index].turns.sort { $0.createdAt < $1.createdAt }
                state.conversations[index].lastTouched = touched
            } else {
                state.conversations.append(NostrConversation(
                    rootEventID: rootEventID,
                    counterpartyPubkey: counterpartyPubkey,
                    firstSeen: touched,
                    lastTouched: touched,
                    turns: [turn]
                ))
            }
            state.conversations.sort { $0.lastTouched > $1.lastTouched }
        }
    }

    private func updateState(_ mutate: (inout CoachNostrAgentState) -> Void) {
        mutate(&state)
        state.save(defaults: defaults)
    }

    private func loadOrCreateKeyPair() throws -> NostrKeyPair {
        if let stored = try NostrCredentialStore.loadKeyPair() {
            return stored
        }
        return try NostrCredentialStore.generateAndSave()
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
    case invalidPubkey
    case invalidMemory

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "No agent key is stored."
        case .notConnected:
            return "Nostr relay is not connected."
        case .invalidPubkey:
            return "Enter an npub, nostr:npub, or 64-character hex pubkey."
        case .invalidMemory:
            return "Memory text cannot be empty."
        }
    }
}
