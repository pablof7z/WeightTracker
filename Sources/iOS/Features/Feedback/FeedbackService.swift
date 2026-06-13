import Foundation

struct FeedbackProjectConfig: Equatable, Sendable {
    let ownerPubkey: String
    let dTag: String
    let agentPubkey: String?

    var aTag: String {
        "31933:\(ownerPubkey):\(dTag)"
    }

    static let weightTracker = FeedbackProjectConfig(
        ownerPubkey: "09d48a1a5dbe13404a729634f1d6ba722d40513468dd713c8ea38ca9b7b6f2c7",
        dTag: "weighttracker",
        agentPubkey: nil
    )
}

struct FeedbackProfile: Equatable, Hashable, Sendable {
    var pubkey: String
    var displayName: String
    var name: String?
    var picture: String?

    var initials: String {
        let words = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(words).uppercased()
        return value.isEmpty ? "?" : value
    }

    var pictureURL: URL? {
        guard let picture, !picture.isEmpty else { return nil }
        return URL(string: picture)
    }
}

struct FeedbackMetadata: Equatable, Hashable, Sendable {
    var rootID: String
    var title: String?
    var summary: String?
    var statusLabel: String?
    var currentActivity: String?
    var createdAt: Int
}

struct FeedbackThread: Identifiable, Equatable, Hashable, Sendable {
    var root: NostrEvent
    var replies: [NostrEvent]
    var metadata: FeedbackMetadata?

    var id: String { root.id }

    var messages: [NostrEvent] {
        ([root] + replies).sorted { lhs, rhs in
            if lhs.created_at == rhs.created_at { return lhs.id < rhs.id }
            return lhs.created_at < rhs.created_at
        }
    }

    var lastActivity: Int {
        max(messages.map(\.created_at).max() ?? root.created_at, metadata?.createdAt ?? 0)
    }

    var title: String {
        if let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return Self.preview(root.content, fallback: "Feedback")
    }

    var summary: String {
        if let summary = metadata?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        return Self.preview(messages.last?.content ?? root.content, fallback: "No messages yet")
    }

    static func preview(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.replacingOccurrences(of: "\n", with: " ").prefix(90))
    }
}

@MainActor
final class FeedbackService: ObservableObject {
    enum IdentityState: Equatable {
        case loading
        case localGenerated
        case importedNsec
        case remoteSigner
        case missing
        case error(String)
    }

    @Published private(set) var identityState: IdentityState = .loading
    @Published private(set) var publicKeyHex: String?
    @Published private(set) var publicKeyNpub: String?
    @Published private(set) var threads: [FeedbackThread] = []
    @Published private(set) var profiles: [String: FeedbackProfile] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var bunkerConnected = false
    @Published private(set) var nostrConnectPending = false
    @Published var lastError: String?

    let projectConfig: FeedbackProjectConfig

    private let feedbackRelay: NostrRelay
    private let profileRelays: [NostrRelay]
    private var keyPair: NostrKeyPair?
    private var nip46Client: Nip46Client?
    private var generatedProfilePublished = false
    private var appName = "WeightTracker"
    private let identityKindKey = "feedback.identity.kind.v1"

    init(projectConfig: FeedbackProjectConfig = .weightTracker) {
        self.projectConfig = projectConfig
        self.feedbackRelay = NostrRelay(url: URL(string: "wss://relay.tenex.chat")!)
        self.profileRelays = [
            NostrRelay(url: URL(string: "wss://relay.tenex.chat")!),
            NostrRelay(url: URL(string: "wss://purplepag.es")!)
        ]
    }

    func start(appName: String) async {
        self.appName = appName
        do {
            let existing = try FeedbackCredentialStore.loadKeyPair()
            let pair = try existing ?? FeedbackCredentialStore.generateAndSave()
            if existing == nil {
                UserDefaults.standard.set("generated", forKey: identityKindKey)
            }
            setIdentity(pair, state: existing == nil ? .localGenerated : storedIdentityState())
            await configureAuthSigners()
            if existing == nil {
                await publishGeneratedProfileIfNeeded()
            }
            if let bunkerURI = FeedbackCredentialStore.loadBunkerURI(), !bunkerURI.isEmpty {
                Task { [weak self] in
                    try? await self?.connectBunker(uri: bunkerURI)
                }
            }
        } catch {
            identityState = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func importNsec(_ secret: String) async {
        do {
            lastError = nil
            let pair = try FeedbackCredentialStore.save(secret: secret)
            UserDefaults.standard.set("nsec", forKey: identityKindKey)
            await disconnectRemoteOnly()
            FeedbackCredentialStore.deleteBunkerURI()
            setIdentity(pair, state: .importedNsec)
            await configureAuthSigners()
            await publishGeneratedProfileIfNeeded()
            await loadThreads()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resetGeneratedIdentity() async {
        do {
            lastError = nil
            FeedbackCredentialStore.delete()
            FeedbackCredentialStore.deleteBunkerURI()
            await disconnectRemoteOnly()
            let pair = try FeedbackCredentialStore.generateAndSave()
            UserDefaults.standard.set("generated", forKey: identityKindKey)
            generatedProfilePublished = false
            setIdentity(pair, state: .localGenerated)
            await configureAuthSigners()
            await publishGeneratedProfileIfNeeded()
            await loadThreads()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func connectBunker(uri: String) async throws {
        lastError = nil
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FeedbackServiceError.emptyMessage }
        let parsed = try BunkerURI(string: trimmed)
        let ephemeral = try NostrKeyPair.generate()
        let client = Nip46Client(localKeyPair: ephemeral)
        try await client.connect(bunkerURI: parsed)
        let pubkey = try await client.getPublicKey()

        await disconnectRemoteOnly()
        nip46Client = client
        keyPair = nil
        publicKeyHex = pubkey
        publicKeyNpub = NostrBech32.encode(hrp: "npub", bytes: Data(nostrHex: pubkey) ?? Data())
        identityState = .remoteSigner
        bunkerConnected = true
        nostrConnectPending = false
        try FeedbackCredentialStore.saveBunkerURI(trimmed)
        FeedbackCredentialStore.delete()
        UserDefaults.standard.set("bunker", forKey: identityKindKey)
        await configureAuthSigners()
        await loadThreads()
    }

    func beginNostrConnect(relayURL: URL) async throws -> String {
        lastError = nil
        await disconnectRemoteOnly()
        let ephemeral = try NostrKeyPair.generate()
        let client = Nip46Client(localKeyPair: ephemeral)
        try await client.startNostrConnect(relayURL: relayURL)

        let metadata = "{\"name\":\"WeightTracker\"}"
        var components = URLComponents()
        components.scheme = "nostrconnect"
        components.host = ephemeral.publicKeyHex
        components.queryItems = [
            URLQueryItem(name: "relay", value: relayURL.absoluteString),
            URLQueryItem(name: "metadata", value: metadata),
            URLQueryItem(name: "perms", value: "sign_event:1,get_public_key"),
            URLQueryItem(name: "callback", value: "weighttracker://nip46")
        ]
        guard let uri = components.url?.absoluteString else { throw FeedbackServiceError.invalidSignerURI }

        nip46Client = client
        nostrConnectPending = true
        Task { [weak self] in
            do {
                try await client.awaitSignerConnect()
                let pubkey = try await client.getPublicKey()
                await MainActor.run {
                    self?.keyPair = nil
                    self?.publicKeyHex = pubkey
                    self?.publicKeyNpub = NostrBech32.encode(hrp: "npub", bytes: Data(nostrHex: pubkey) ?? Data())
                    self?.identityState = .remoteSigner
                    self?.bunkerConnected = true
                    self?.nostrConnectPending = false
                    FeedbackCredentialStore.delete()
                    UserDefaults.standard.set("bunker", forKey: self?.identityKindKey ?? "feedback.identity.kind.v1")
                }
                await self?.loadThreads()
            } catch {
                await MainActor.run {
                    self?.nip46Client = nil
                    self?.nostrConnectPending = false
                    self?.lastError = error.localizedDescription
                }
            }
        }

        return uri
    }

    func disconnectRemoteSigner() async {
        await disconnectRemoteOnly()
        FeedbackCredentialStore.deleteBunkerURI()
        await resetGeneratedIdentity()
    }

    func loadThreads(mineOnly: Bool = true) async {
        guard let myPubkey = await ensurePublicKey() else { return }
        isLoading = true
        defer { isLoading = false }

        let projectTag = projectConfig.aTag
        let visibleEvents = await feedbackRelay.fetch(
            filter: NostrFilter(kinds: [1, 513], limit: 200, aTags: [projectTag]),
            timeoutSeconds: 7
        )

        let kind1 = visibleEvents.filter { $0.kind == 1 }
        let roots = kind1
            .filter { Self.isRootFeedbackEvent($0, projectTag: projectTag) }
            .filter { !mineOnly || $0.pubkey == myPubkey }
        let repliesByRoot = Dictionary(grouping: kind1.filter { !Self.isRootFeedbackEvent($0, projectTag: projectTag) }) {
            $0.conversationRootID()
        }
        let metadataByRoot = Self.latestMetadataByRoot(
            events: visibleEvents.filter { $0.kind == 513 },
            projectTag: projectTag
        )

        threads = roots
            .map { root in
                FeedbackThread(
                    root: root,
                    replies: repliesByRoot[root.id] ?? [],
                    metadata: metadataByRoot[root.id]
                )
            }
            .sorted { lhs, rhs in
                if lhs.lastActivity == rhs.lastActivity { return lhs.id < rhs.id }
                return lhs.lastActivity > rhs.lastActivity
            }

        let pubkeys = Set(threads.flatMap { $0.messages.map(\.pubkey) })
        await loadProfiles(pubkeys: pubkeys)
    }

    func loadThread(rootID: String) async -> FeedbackThread? {
        let projectTag = projectConfig.aTag
        async let roots = feedbackRelay.fetch(filter: NostrFilter(ids: [rootID]), timeoutSeconds: 5)
        async let replies = feedbackRelay.fetch(filter: NostrFilter(kinds: [1], limit: 200, eTags: [rootID]), timeoutSeconds: 5)
        async let metadata = feedbackRelay.fetch(filter: NostrFilter(kinds: [513], limit: 20, eTags: [rootID]), timeoutSeconds: 5)

        let fetchedRoots = await roots
        guard let root = fetchedRoots.first(where: { Self.event($0, hasATag: projectTag) }) else {
            return threads.first(where: { $0.id == rootID })
        }

        let fetchedReplies = await replies
            .filter { Self.event($0, hasATag: projectTag) }
            .filter { $0.conversationRootID() == rootID }
        let fetchedMetadata = await metadata
        let metadataByRoot = Self.latestMetadataByRoot(events: fetchedMetadata, projectTag: projectTag)
        let thread = FeedbackThread(root: root, replies: fetchedReplies, metadata: metadataByRoot[rootID])
        replaceThread(thread)
        await loadProfiles(pubkeys: Set(thread.messages.map(\.pubkey)))
        return thread
    }

    @discardableResult
    func sendRootFeedback(_ content: String) async throws -> FeedbackThread {
        guard await ensurePublicKey() != nil else {
            throw FeedbackServiceError.missingIdentity
        }
        try await publishGeneratedProfileIfNeededThrowing()

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FeedbackServiceError.emptyMessage }

        var tags: [[String]] = [
            ["a", projectConfig.aTag],
            ["client", "weighttracker-ios"]
        ]
        if let agentPubkey = projectConfig.agentPubkey {
            tags.append(["p", agentPubkey])
        }

        let event = try await sign(kind: 1, content: trimmed, tags: tags)
        try await publishFeedbackEvent(event)
        let thread = FeedbackThread(root: event, replies: [], metadata: nil)
        threads.insert(thread, at: 0)
        await loadProfiles(pubkeys: [event.pubkey])
        return thread
    }

    @discardableResult
    func sendReply(content: String, in thread: FeedbackThread) async throws -> FeedbackThread {
        guard let myPubkey = await ensurePublicKey() else {
            throw FeedbackServiceError.missingIdentity
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FeedbackServiceError.emptyMessage }

        var tags: [[String]] = [
            ["a", projectConfig.aTag],
            ["e", thread.root.id, "", "root"],
            ["client", "weighttracker-ios"]
        ]

        if let lastOther = thread.messages.last(where: { $0.pubkey != myPubkey })?.pubkey {
            tags.append(["p", lastOther])
        } else if thread.root.pubkey != myPubkey {
            tags.append(["p", thread.root.pubkey])
        } else if let agentPubkey = projectConfig.agentPubkey {
            tags.append(["p", agentPubkey])
        }

        let event = try await sign(kind: 1, content: trimmed, tags: tags)
        try await publishFeedbackEvent(event)
        let updated = FeedbackThread(root: thread.root, replies: thread.replies + [event], metadata: thread.metadata)
        replaceThread(updated)
        await loadProfiles(pubkeys: [event.pubkey])
        return updated
    }

    func profile(for pubkey: String) -> FeedbackProfile {
        if let profile = profiles[pubkey] { return profile }
        return FeedbackProfile(
            pubkey: pubkey,
            displayName: CoachNostrAgentService.shortNpub(pubkey),
            name: nil,
            picture: nil
        )
    }

    private func ensurePublicKey() async -> String? {
        if let publicKeyHex { return publicKeyHex }
        await start(appName: appName)
        return publicKeyHex
    }

    private func setIdentity(_ pair: NostrKeyPair, state: IdentityState) {
        keyPair = pair
        publicKeyHex = pair.publicKeyHex
        publicKeyNpub = pair.npub
        identityState = state
        bunkerConnected = false
        nostrConnectPending = false
    }

    private func configureAuthSigners() async {
        await feedbackRelay.setAuthSigner { [weak self] relayURL, challenge in
            guard let self else { return nil }
            let tags = [["relay", relayURL], ["challenge", challenge]]
            return try? await self.sign(kind: 22242, content: "", tags: tags)
        }
        for relay in profileRelays {
            await relay.setAuthSigner { [weak self] relayURL, challenge in
                guard let self else { return nil }
                let tags = [["relay", relayURL], ["challenge", challenge]]
                return try? await self.sign(kind: 22242, content: "", tags: tags)
            }
        }
    }

    private func storedIdentityState() -> IdentityState {
        switch UserDefaults.standard.string(forKey: identityKindKey) {
        case "nsec":
            return .importedNsec
        case "bunker":
            return .remoteSigner
        default:
            return .localGenerated
        }
    }

    private func disconnectRemoteOnly() async {
        await nip46Client?.disconnect()
        nip46Client = nil
        bunkerConnected = false
        nostrConnectPending = false
    }

    private func sign(kind: Int, content: String, tags: [[String]]) async throws -> NostrEvent {
        if let nip46Client {
            return try await nip46Client.signEvent(kind: kind, content: content, tags: tags)
        }
        guard let keyPair else { throw FeedbackServiceError.missingIdentity }
        return try NostrEvent.signed(kind: kind, content: content, tags: tags, keyPair: keyPair)
    }

    func signSharedFeedbackEvent(kind: Int, content: String, tags: [[String]]) async throws -> NostrEvent {
        try await sign(kind: kind, content: content, tags: tags)
    }

    private func publishFeedbackEvent(_ event: NostrEvent) async throws {
        do {
            try await feedbackRelay.publishAndAwaitOK(event, timeout: 8)
        } catch let error as NostrRelayError {
            guard case .rejected(let message) = error,
                  message.hasPrefix("auth-required:")
            else {
                throw error
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            try await feedbackRelay.publishAndAwaitOK(event, timeout: 8)
        }
    }

    private func publishGeneratedProfileIfNeeded() async {
        do {
            try await publishGeneratedProfileIfNeededThrowing()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func publishGeneratedProfileIfNeededThrowing() async throws {
        guard !generatedProfilePublished, let keyPair else { return }
        let profile = Self.generatedProfile(pubkey: keyPair.publicKeyHex, appName: appName)
        let data = try JSONSerialization.data(withJSONObject: profile, options: [.sortedKeys, .withoutEscapingSlashes])
        guard let content = String(data: data, encoding: .utf8) else {
            throw FeedbackServiceError.invalidProfile
        }
        let event = try NostrEvent.signed(kind: 0, content: content, tags: [], keyPair: keyPair)

        for relay in profileRelays {
            try? await relay.publishAndAwaitOK(event, timeout: 5)
        }
        generatedProfilePublished = true
        profiles[keyPair.publicKeyHex] = FeedbackProfile(
            pubkey: keyPair.publicKeyHex,
            displayName: profile["display_name"] ?? "Feedback User",
            name: profile["name"],
            picture: profile["picture"]
        )
    }

    private func loadProfiles(pubkeys: Set<String>) async {
        let missing = pubkeys.filter { profiles[$0] == nil }
        guard !missing.isEmpty else { return }

        var latest: [String: (event: NostrEvent, profile: FeedbackProfile)] = [:]
        for relay in profileRelays {
            let events = await relay.fetch(
                filter: NostrFilter(authors: Array(missing), kinds: [0], limit: missing.count * 2),
                timeoutSeconds: 4
            )
            for event in events where event.kind == 0 {
                guard let profile = Self.profile(from: event) else { continue }
                if let current = latest[event.pubkey], current.event.created_at > event.created_at {
                    continue
                }
                latest[event.pubkey] = (event, profile)
            }
        }

        for pubkey in missing where latest[pubkey] == nil {
            latest[pubkey] = (
                NostrEvent(id: "", pubkey: pubkey, created_at: 0, kind: 0, tags: [], content: "", sig: ""),
                FeedbackProfile(pubkey: pubkey, displayName: CoachNostrAgentService.shortNpub(pubkey), name: nil, picture: nil)
            )
        }

        for (pubkey, value) in latest {
            profiles[pubkey] = value.profile
        }
    }

    private func replaceThread(_ thread: FeedbackThread) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.append(thread)
        }
        threads.sort { lhs, rhs in
            if lhs.lastActivity == rhs.lastActivity { return lhs.id < rhs.id }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    private static func isRootFeedbackEvent(_ event: NostrEvent, projectTag: String) -> Bool {
        event.kind == 1
            && Self.event(event, hasATag: projectTag)
            && !event.eTags.contains(where: { $0.count >= 4 && $0[3] == "root" })
    }

    private static func event(_ event: NostrEvent, hasATag projectTag: String) -> Bool {
        event.aTags.contains { $0.count >= 2 && $0[1] == projectTag }
    }

    private static func latestMetadataByRoot(events: [NostrEvent], projectTag: String) -> [String: FeedbackMetadata] {
        var output: [String: FeedbackMetadata] = [:]
        for event in events where event.kind == 513 && Self.event(event, hasATag: projectTag) {
            guard let rootID = event.eTags.first(where: { $0.count >= 2 })?[1] else { continue }
            guard output[rootID]?.createdAt ?? 0 <= event.created_at else { continue }
            output[rootID] = metadata(from: event, rootID: rootID)
        }
        return output
    }

    private static func metadata(from event: NostrEvent, rootID: String) -> FeedbackMetadata {
        var title = tagValue("title", in: event.tags)
        var summary = tagValue("summary", in: event.tags)
        var statusLabel = tagValue("status-label", in: event.tags)
        let currentActivity = tagValue("status-current-activity", in: event.tags)

        if (!event.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
           let data = event.content.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = title ?? object["title"] as? String
            summary = summary ?? object["summary"] as? String
            statusLabel = statusLabel ?? object["status_label"] as? String ?? object["status"] as? String
        }

        return FeedbackMetadata(
            rootID: rootID,
            title: title,
            summary: summary,
            statusLabel: statusLabel,
            currentActivity: currentActivity,
            createdAt: event.created_at
        )
    }

    private static func tagValue(_ name: String, in tags: [[String]]) -> String? {
        tags.first(where: { $0.count >= 2 && $0[0] == name })?[1]
    }

    private static func profile(from event: NostrEvent) -> FeedbackProfile? {
        guard let data = event.content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let displayName = (object["display_name"] as? String)
            ?? (object["displayName"] as? String)
            ?? (object["name"] as? String)
            ?? CoachNostrAgentService.shortNpub(event.pubkey)
        return FeedbackProfile(
            pubkey: event.pubkey,
            displayName: displayName,
            name: object["name"] as? String,
            picture: object["picture"] as? String
        )
    }

    private static func generatedProfile(pubkey: String, appName: String) -> [String: String] {
        let seed = String(pubkey.prefix(16))
        let adjectives = ["Bright", "Quiet", "Swift", "Clear", "North", "Steady", "Fresh", "Calm"]
        let nouns = ["Signal", "Notebook", "Harbor", "Lantern", "Thread", "Field", "Marker", "Anchor"]
        let adjective = adjectives[stableIndex(seed + "-a", count: adjectives.count)]
        let noun = nouns[stableIndex(seed + "-n", count: nouns.count)]
        return [
            "name": "\(adjective.lowercased())-\(noun.lowercased())-\(pubkey.prefix(4))",
            "display_name": "\(adjective) \(noun)",
            "about": "Feedback identity generated by \(appName).",
            "picture": "https://api.dicebear.com/9.x/personas/svg?seed=\(seed)"
        ]
    }

    private static func stableIndex(_ value: String, count: Int) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Int(hash % UInt64(count))
    }
}

enum FeedbackServiceError: LocalizedError {
    case missingIdentity
    case emptyMessage
    case invalidProfile
    case invalidSignerURI

    var errorDescription: String? {
        switch self {
        case .missingIdentity:
            return "No feedback identity is available."
        case .emptyMessage:
            return "Feedback cannot be empty."
        case .invalidProfile:
            return "Could not encode the feedback profile."
        case .invalidSignerURI:
            return "Could not create a signer connection link."
        }
    }
}
