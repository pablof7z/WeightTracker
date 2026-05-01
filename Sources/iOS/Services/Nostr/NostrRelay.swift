import Foundation

actor NostrRelay {
    enum Frame: Sendable {
        case event(subscriptionID: String, event: NostrEvent)
        case eose(subscriptionID: String)
        case ok(eventID: String, accepted: Bool, message: String)
        case notice(message: String)
        case auth(challenge: String)
        case connected
        case disconnected(error: String?)
    }

    nonisolated let url: URL

    private var session: URLSession
    private var task: URLSessionWebSocketTask?
    private var supervisor: Task<Void, Never>?
    private var stopped = false
    private var reconnectAttempt = 0
    private var activeSubscriptions: [String: NostrFilter] = [:]
    private var primaryContinuation: AsyncStream<Frame>.Continuation?
    private var pendingFetches: [String: PendingFetch] = [:]
    private var pendingPublishes: [String: PendingPublish] = [:]
    private var authSigner: (@Sendable (String, String) async -> NostrEvent?)?

    private struct PendingFetch {
        var collected: [NostrEvent]
        var continuation: CheckedContinuation<[NostrEvent], Never>
    }

    private struct PendingPublish {
        var continuation: CheckedContinuation<(Bool, String), Never>
        var watchdog: Task<Void, Never>
    }

    init(url: URL) {
        self.url = url
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    func setAuthSigner(_ signer: (@Sendable (String, String) async -> NostrEvent?)?) {
        authSigner = signer
    }

    func events() -> AsyncStream<Frame> {
        ensureSupervisorRunning()
        return AsyncStream<Frame> { continuation in
            self.primaryContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.stop() }
            }
        }
    }

    func stop() {
        stopped = true
        supervisor?.cancel()
        supervisor = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        primaryContinuation?.finish()
        primaryContinuation = nil

        for (_, pending) in pendingFetches {
            pending.continuation.resume(returning: pending.collected)
        }
        pendingFetches.removeAll()

        for (_, pending) in pendingPublishes {
            pending.watchdog.cancel()
            pending.continuation.resume(returning: (true, "stopped"))
        }
        pendingPublishes.removeAll()
        activeSubscriptions.removeAll()
    }

    func subscribe(id: String, filter: NostrFilter) async {
        activeSubscriptions[id] = filter
        await sendREQ(id: id, filter: filter)
    }

    func unsubscribe(id: String) async {
        activeSubscriptions.removeValue(forKey: id)
        await sendJSON(["CLOSE", id])
    }

    func fetch(filter: NostrFilter, timeoutSeconds: Double = 5) async -> [NostrEvent] {
        ensureSupervisorRunning()
        let subscriptionID = "fetch-\(UUID().uuidString.prefix(8))"
        let events: [NostrEvent] = await withCheckedContinuation { continuation in
            pendingFetches[subscriptionID] = PendingFetch(collected: [], continuation: continuation)
            Task { await self.sendREQ(id: subscriptionID, filter: filter) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self.completeFetchIfStillPending(id: subscriptionID)
            }
        }
        await sendJSON(["CLOSE", subscriptionID])
        return events
    }

    func publish(_ event: NostrEvent) async {
        ensureSupervisorRunning()
        await sendJSON(["EVENT", eventDictionary(event)])
    }

    func publishAndAwaitOK(_ event: NostrEvent, timeout: Double = 5) async throws {
        ensureSupervisorRunning()
        let eventID = event.id
        let result: (Bool, String) = await withCheckedContinuation { continuation in
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.completePendingPublishIfStillWaiting(id: eventID)
            }
            pendingPublishes[eventID] = PendingPublish(continuation: continuation, watchdog: watchdog)
            Task { await self.publish(event) }
        }

        if !result.0 {
            throw NostrRelayError.rejected(message: result.1)
        }
    }

    private func ensureSupervisorRunning() {
        guard !stopped else { return }
        if let supervisor, !supervisor.isCancelled { return }
        supervisor = Task { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        while !Task.isCancelled, !stopped {
            do {
                try await connectOnce()
            } catch {
                if stopped { return }
                primaryContinuation?.yield(.disconnected(error: String(describing: error)))
                let delay = backoffSeconds()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func connectOnce() async throws {
        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        reconnectAttempt = 0
        primaryContinuation?.yield(.connected)

        for (id, filter) in activeSubscriptions {
            await sendREQ(id: id, filter: filter)
        }

        while !Task.isCancelled, !stopped {
            let message = try await socket.receive()
            handleIncoming(message)
        }
        throw NostrError.relayClosed
    }

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let value):
            text = value
        case .data(let data):
            text = String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = array.first as? String else {
            return
        }

        switch type {
        case "EVENT":
            guard array.count >= 3,
                  let subscriptionID = array[1] as? String,
                  let eventObject = array[2] as? [String: Any],
                  let eventData = try? JSONSerialization.data(withJSONObject: eventObject),
                  let event = try? JSONDecoder().decode(NostrEvent.self, from: eventData) else {
                return
            }
            if pendingFetches[subscriptionID] != nil {
                pendingFetches[subscriptionID]?.collected.append(event)
            } else {
                primaryContinuation?.yield(.event(subscriptionID: subscriptionID, event: event))
            }

        case "EOSE":
            guard array.count >= 2, let subscriptionID = array[1] as? String else { return }
            if let pending = pendingFetches.removeValue(forKey: subscriptionID) {
                pending.continuation.resume(returning: pending.collected)
            } else {
                primaryContinuation?.yield(.eose(subscriptionID: subscriptionID))
            }

        case "OK":
            guard array.count >= 4,
                  let eventID = array[1] as? String,
                  let accepted = array[2] as? Bool,
                  let message = array[3] as? String else {
                return
            }
            primaryContinuation?.yield(.ok(eventID: eventID, accepted: accepted, message: message))
            if let pending = pendingPublishes.removeValue(forKey: eventID) {
                pending.watchdog.cancel()
                pending.continuation.resume(returning: (accepted, message))
            }

        case "NOTICE":
            if array.count >= 2, let message = array[1] as? String {
                primaryContinuation?.yield(.notice(message: message))
            }

        case "AUTH":
            if array.count >= 2, let challenge = array[1] as? String {
                primaryContinuation?.yield(.auth(challenge: challenge))
                if let authSigner {
                    let relayURL = url.absoluteString
                    Task {
                        guard let authEvent = await authSigner(relayURL, challenge) else { return }
                        await self.sendJSON(["AUTH", self.eventDictionary(authEvent)])
                    }
                }
            }

        default:
            break
        }
    }

    private func completeFetchIfStillPending(id: String) {
        guard let pending = pendingFetches.removeValue(forKey: id) else { return }
        pending.continuation.resume(returning: pending.collected)
    }

    private func completePendingPublishIfStillWaiting(id: String) {
        guard let pending = pendingPublishes.removeValue(forKey: id) else { return }
        pending.continuation.resume(returning: (true, "timeout"))
    }

    private func sendREQ(id: String, filter: NostrFilter) async {
        guard let filterData = try? JSONEncoder().encode(filter),
              let filterObject = try? JSONSerialization.jsonObject(with: filterData) as? [String: Any] else {
            return
        }
        await sendJSON(["REQ", id, filterObject])
    }

    private func sendJSON(_ object: [Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8),
              let task else {
            return
        }

        do {
            try await task.send(.string(text))
        } catch {
            primaryContinuation?.yield(.disconnected(error: String(describing: error)))
        }
    }

    private func eventDictionary(_ event: NostrEvent) -> [String: Any] {
        [
            "id": event.id,
            "pubkey": event.pubkey,
            "created_at": event.created_at,
            "kind": event.kind,
            "tags": event.tags,
            "content": event.content,
            "sig": event.sig
        ]
    }

    private func backoffSeconds() -> Double {
        reconnectAttempt = min(reconnectAttempt + 1, 5)
        return min(pow(2.0, Double(reconnectAttempt)), 30)
    }
}

enum NostrRelayError: LocalizedError {
    case rejected(message: String)

    var errorDescription: String? {
        switch self {
        case .rejected(let message):
            return "Relay rejected event: \(message)"
        }
    }
}

extension NostrRelay {
    nonisolated var displayURL: String {
        url.absoluteString
    }
}
