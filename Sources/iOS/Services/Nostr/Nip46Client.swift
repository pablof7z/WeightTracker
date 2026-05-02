import Foundation

enum Nip46Error: LocalizedError, CustomStringConvertible {
    case invalidBunkerURI(String)
    case notConnected
    case timeout
    case disconnected
    case signerError(String)
    case invalidResponse

    var description: String {
        switch self {
        case .invalidBunkerURI(let value): return "Invalid bunker URI: \(value)"
        case .notConnected: return "NIP-46 signer not connected"
        case .timeout: return "NIP-46 request timed out"
        case .disconnected: return "NIP-46 signer disconnected"
        case .signerError(let message): return "Signer error: \(message)"
        case .invalidResponse: return "Unexpected NIP-46 response format"
        }
    }

    var errorDescription: String? { description }
}

struct BunkerURI {
    let remotePubkeyHex: String
    let relayURL: String
    let secret: String?

    init(string: String) throws {
        guard let url = URL(string: string), url.scheme == "bunker" else {
            throw Nip46Error.invalidBunkerURI(string)
        }
        let host = url.host ?? ""
        guard !host.isEmpty else { throw Nip46Error.invalidBunkerURI(string) }
        remotePubkeyHex = host

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let relay = items.first(where: { $0.name == "relay" })?.value, !relay.isEmpty else {
            throw Nip46Error.invalidBunkerURI("missing relay parameter")
        }
        relayURL = relay
        secret = items.first(where: { $0.name == "secret" })?.value
    }
}

actor Nip46Client {
    private let localKeyPair: NostrKeyPair
    private(set) var userPubkeyHex: String?
    private var remotePubkeyHex = ""

    private var relay: NostrRelay?
    private var listenerTask: Task<Void, Never>?
    private var relayConnectedContinuation: CheckedContinuation<Void, Error>?
    private var nostrConnectContinuation: CheckedContinuation<Void, Error>?
    private var nostrConnectTimeoutTask: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]

    private let subID = "nip46"
    private static let timeoutNanoseconds: UInt64 = 30_000_000_000

    init(localKeyPair: NostrKeyPair) {
        self.localKeyPair = localKeyPair
    }

    func connect(bunkerURI: BunkerURI) async throws {
        remotePubkeyHex = bunkerURI.remotePubkeyHex

        guard let url = URL(string: bunkerURI.relayURL),
              url.scheme == "ws" || url.scheme == "wss"
        else {
            throw Nip46Error.invalidBunkerURI("invalid relay URL: \(bunkerURI.relayURL)")
        }

        let relay = NostrRelay(url: url)
        self.relay = relay

        let filter = NostrFilter(kinds: [24133], pTags: [localKeyPair.publicKeyHex])
        await relay.subscribe(id: subID, filter: filter)

        listenerTask = Task { [weak self] in
            guard let self else { return }
            await self.listenLoop(relay: relay)
        }

        try await withCheckedThrowingContinuation { continuation in
            relayConnectedContinuation = continuation
        }

        let id = UUID().uuidString
        let params: [String] = [localKeyPair.publicKeyHex, bunkerURI.secret ?? "", ""]
        let requestJSON = try buildRequestJSON(id: id, method: "connect", params: params)
        let event = try buildEncryptedEvent(content: requestJSON)
        await relay.publish(event)
        _ = try await request(id: id)
    }

    func startNostrConnect(relayURL: URL) async throws {
        let relay = NostrRelay(url: relayURL)
        self.relay = relay

        let filter = NostrFilter(kinds: [24133], pTags: [localKeyPair.publicKeyHex])
        await relay.subscribe(id: subID, filter: filter)

        listenerTask = Task { [weak self] in
            guard let self else { return }
            await self.listenLoop(relay: relay)
        }

        try await withCheckedThrowingContinuation { continuation in
            relayConnectedContinuation = continuation
        }
    }

    func awaitSignerConnect() async throws {
        try await withCheckedThrowingContinuation { continuation in
            nostrConnectContinuation = continuation
            nostrConnectTimeoutTask = Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard let pending = self.nostrConnectContinuation else { return }
                self.nostrConnectContinuation = nil
                self.nostrConnectTimeoutTask = nil
                pending.resume(throwing: Nip46Error.timeout)
            }
        }
    }

    func getPublicKey() async throws -> String {
        let id = UUID().uuidString
        let requestJSON = try buildRequestJSON(id: id, method: "get_public_key", params: [])
        let event = try buildEncryptedEvent(content: requestJSON)
        guard let relay else { throw Nip46Error.notConnected }
        await relay.publish(event)
        let pubkey = try await request(id: id)
        userPubkeyHex = pubkey
        return pubkey
    }

    func signEvent(kind: Int, content: String, tags: [[String]]) async throws -> NostrEvent {
        guard let pubkey = userPubkeyHex else { throw Nip46Error.notConnected }
        guard let relay else { throw Nip46Error.notConnected }

        let createdAt = Int(Date().timeIntervalSince1970)
        let eventID = try NostrEvent.computeID(
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        ).id
        let template = NostrEvent(
            id: eventID,
            pubkey: pubkey,
            created_at: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: ""
        )
        let templateJSON = (try? String(data: JSONEncoder().encode(template), encoding: .utf8)) ?? ""

        let id = UUID().uuidString
        let requestJSON = try buildRequestJSON(id: id, method: "sign_event", params: [templateJSON])
        let event = try buildEncryptedEvent(content: requestJSON)
        await relay.publish(event)

        let resultJSON = try await request(id: id)
        guard let data = resultJSON.data(using: .utf8),
              let signed = try? JSONDecoder().decode(NostrEvent.self, from: data)
        else {
            throw Nip46Error.invalidResponse
        }
        return signed
    }

    func disconnect() {
        listenerTask?.cancel()
        listenerTask = nil
        relayConnectedContinuation?.resume(throwing: Nip46Error.disconnected)
        relayConnectedContinuation = nil
        nostrConnectContinuation?.resume(throwing: Nip46Error.disconnected)
        nostrConnectContinuation = nil
        nostrConnectTimeoutTask?.cancel()
        nostrConnectTimeoutTask = nil
        for (_, task) in timeouts { task.cancel() }
        timeouts.removeAll()
        for (_, continuation) in pending { continuation.resume(throwing: Nip46Error.disconnected) }
        pending.removeAll()
        if let relay {
            Task { await relay.stop() }
        }
        self.relay = nil
        userPubkeyHex = nil
    }

    deinit {
        for (_, continuation) in pending {
            continuation.resume(throwing: Nip46Error.disconnected)
        }
    }

    private func listenLoop(relay: NostrRelay) async {
        for await frame in await relay.events() {
            switch frame {
            case .connected:
                relayConnectedContinuation?.resume()
                relayConnectedContinuation = nil
            case .disconnected(let reason):
                let error = Nip46Error.signerError(reason ?? "relay disconnected")
                relayConnectedContinuation?.resume(throwing: error)
                relayConnectedContinuation = nil
            case .event(let subscriptionID, let event) where subscriptionID == subID && event.kind == 24133:
                handleEvent(event)
            default:
                break
            }
        }
    }

    private func handleEvent(_ event: NostrEvent) {
        let senderPubkey = remotePubkeyHex.isEmpty ? event.pubkey : remotePubkeyHex
        guard event.pubkey == senderPubkey else { return }
        guard let plaintext = try? Nip44Crypto.decrypt(
            payload: event.content,
            senderPubKeyHex: senderPubkey,
            recipientPrivKeyHex: localKeyPair.privateKeyHex
        ) else { return }

        struct Message: Decodable {
            let id: String
            let method: String?
            let params: [String]?
            let result: String?
            let error: String?
        }

        guard let message = try? JSONDecoder().decode(Message.self, from: Data(plaintext.utf8)) else { return }

        if let method = message.method {
            handleSignerRequest(id: message.id, method: method, signerPubkey: event.pubkey)
        } else {
            timeouts.removeValue(forKey: message.id)?.cancel()
            if let continuation = pending.removeValue(forKey: message.id) {
                if let error = message.error, !error.isEmpty {
                    continuation.resume(throwing: Nip46Error.signerError(error))
                } else {
                    continuation.resume(returning: message.result ?? "")
                }
            }
        }
    }

    private func handleSignerRequest(id: String, method: String, signerPubkey: String) {
        guard method == "connect" else { return }
        remotePubkeyHex = signerPubkey
        nostrConnectTimeoutTask?.cancel()
        nostrConnectTimeoutTask = nil
        Task {
            let ackObject: [String: String] = ["id": id, "result": "ack"]
            guard let data = try? JSONSerialization.data(withJSONObject: ackObject),
                  let ackJSON = String(data: data, encoding: .utf8),
                  let ack = try? buildEncryptedEvent(content: ackJSON)
            else { return }
            await relay?.publish(ack)
        }
        nostrConnectContinuation?.resume()
        nostrConnectContinuation = nil
    }

    private func request(id: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task.detached { [weak self, id] in
                try? await Task.sleep(nanoseconds: Nip46Client.timeoutNanoseconds)
                await self?.expirePending(id: id)
            }
        }
    }

    private func expirePending(id: String) {
        timeouts.removeValue(forKey: id)
        pending.removeValue(forKey: id)?.resume(throwing: Nip46Error.timeout)
    }

    private func buildRequestJSON(id: String, method: String, params: [String]) throws -> String {
        let object: [String: Any] = ["id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func buildEncryptedEvent(content: String) throws -> NostrEvent {
        let encrypted = try Nip44Crypto.encrypt(
            plaintext: content,
            recipientPubKeyHex: remotePubkeyHex,
            senderPrivKeyHex: localKeyPair.privateKeyHex
        )
        return try NostrEvent.signed(
            kind: 24133,
            content: encrypted,
            tags: [["p", remotePubkeyHex]],
            keyPair: localKeyPair
        )
    }
}
