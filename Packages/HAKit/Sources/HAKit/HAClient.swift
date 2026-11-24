import Foundation
import os

public enum HAClientError: Error, Sendable, LocalizedError, Equatable {
    case authFailed(String)
    case notConnected
    case protocolError(String)
    case serviceError(code: String, message: String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .authFailed(let m): "Authentication failed: \(m)"
        case .notConnected: "Not connected to Home Assistant"
        case .protocolError(let m): "Unexpected reply from Home Assistant: \(m)"
        case .serviceError(let code, let m): "Home Assistant error (\(code)): \(m)"
        case .timeout: "Home Assistant didn't answer in time"
        }
    }
}

/// Live connection to the Home Assistant WebSocket API.
///
/// Authenticates, subscribes to a list of entities with `subscribe_entities` (changeable with
/// `updateSubscription`), keeps the
/// socket alive with pings and reconnects with exponential backoff (1 s → 30 s).
/// Events are delivered on `events`; feed them into an `EntityStore`.
public actor HAClient {
    public struct Configuration: Sendable, Equatable {
        public var baseURL: URL
        public var token: String
        public init(baseURL: URL, token: String) {
            self.baseURL = baseURL
            self.token = token
        }

        var webSocketURL: URL? {
            guard var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
            c.scheme = (c.scheme == "https") ? "wss" : "ws"
            var path = c.path
            while path.hasSuffix("/") { path.removeLast() }
            c.path = path + "/api/websocket"
            return c.url
        }
    }

    public enum Event: Sendable {
        case status(ConnectionStatus)
        /// A `subscribe_entities` event payload (compressed states).
        case entities(JSONValue)
    }

    public nonisolated let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    private let session: URLSession
    private let log = Logger(subsystem: "HAKit", category: "HAClient")

    private var config: Configuration?
    private var entityIDs: [String] = []
    private var generation = 0
    private var runTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var subscriptionID: Int?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var lastPongAt = Date.now

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    public var isRunning: Bool { runTask != nil }

    // MARK: Lifecycle

    /// Starts (or keeps) the connection. Calling again with the same arguments is a no-op.
    public func start(_ configuration: Configuration, entityIDs: [String]) {
        if runTask != nil, configuration == config, entityIDs == self.entityIDs { return }
        teardown()
        config = configuration
        self.entityIDs = entityIDs
        generation += 1
        let gen = generation
        runTask = Task { await self.runLoop(generation: gen) }
    }

    /// Disconnects and stops reconnecting.
    public func stop() {
        guard runTask != nil else { return }
        teardown()
        generation += 1
        continuation.yield(.status(.disconnected))
    }

    /// Drops the socket and connects again right away (after wake, or a settings change).
    public func reconnect() {
        guard let config else { return }
        let ids = entityIDs
        teardown()
        self.config = nil
        start(config, entityIDs: ids)
    }

    private func teardown() {
        runTask?.cancel()
        runTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        subscriptionID = nil
        failPending(HAClientError.notConnected)
    }

    private func emit(_ status: ConnectionStatus, _ gen: Int) {
        guard gen == generation else { return }
        continuation.yield(.status(status))
    }

    private func runLoop(generation gen: Int) async {
        var attempt = 0
        var lastStatus: ConnectionStatus?
        while !Task.isCancelled, gen == generation, let config {
            if attempt == 0 {
                emit(.connecting, gen)
            }
            var stage = Stage.connecting
            do {
                try await connectOnce(config, generation: gen, stage: &stage)
            } catch let error as HAClientError {
                if case .authFailed = error {
                    log.error("Auth failed")
                    emit(.authFailed, gen)
                    runTask = nil
                    return
                }
                log.info("Connection ended: \(error.localizedDescription, privacy: .public)")
            } catch {
                log.info("Connection ended: \(error.localizedDescription, privacy: .public)")
            }
            if Task.isCancelled || gen != generation { return }

            // Couldn't even reach the server → probably away from home.
            let status: ConnectionStatus = stage == .connecting ? .notOnHomeNetwork : .reconnecting
            if status != lastStatus || attempt == 0 { emit(status, gen) }
            lastStatus = status

            attempt = (stage == .subscribed) ? 1 : attempt + 1
            let delay = min(30.0, pow(2.0, Double(max(attempt - 1, 0))))
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private enum Stage { case connecting, authenticating, subscribed }

    private func connectOnce(_ config: Configuration, generation gen: Int, stage: inout Stage) async throws {
        guard let url = config.webSocketURL else { throw HAClientError.protocolError("Invalid URL") }
        let task = session.webSocketTask(with: url)
        // Registry lists on large installs can be several MB.
        task.maximumMessageSize = 64 * 1024 * 1024
        socket = task
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
            if socket === task {
                socket = nil
                subscriptionID = nil
            }
            failPending(HAClientError.notConnected)
        }

        let hello = try await receive(task, timeout: .seconds(8))
        guard hello["type"]?.string == "auth_required" else {
            throw HAClientError.protocolError("expected auth_required")
        }
        stage = .authenticating

        try await send(["type": "auth", "access_token": .string(config.token)], on: task)
        let auth = try await receive(task, timeout: .seconds(8))
        switch auth["type"]?.string {
        case "auth_ok": break
        case "auth_invalid": throw HAClientError.authFailed(auth["message"]?.string ?? "invalid token")
        default: throw HAClientError.protocolError("unexpected auth reply")
        }

        let subID = allocateID()
        subscriptionID = subID
        try await send(
            ["id": .integer(subID), "type": "subscribe_entities", "entity_ids": .strings(entityIDs)], on: task)
        stage = .subscribed
        emit(.connected, gen)
        log.info("Connected, subscribed to \(self.entityIDs.count) entities")

        lastPongAt = .now
        let pinger = Task { await self.pingLoop(task) }
        defer { pinger.cancel() }

        while !Task.isCancelled {
            let message = try await receive(task, timeout: nil)
            handle(message, generation: gen)
        }
    }

    private func pingLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled { return }
            if Date.now.timeIntervalSince(lastPongAt) > 75 {
                log.info("No pong for 75 s, dropping socket")
                task.cancel(with: .goingAway, reason: nil)
                return
            }
            try? await send(["id": .integer(allocateID()), "type": "ping"], on: task)
        }
    }

    // MARK: Messages

    private func handle(_ message: JSONValue, generation gen: Int) {
        if case .array(let batch) = message {
            for m in batch { handle(m, generation: gen) }
            return
        }
        let id = message["id"]?.int
        switch message["type"]?.string {
        case "event":
            if id != nil, id == subscriptionID, let event = message["event"], gen == generation {
                continuation.yield(.entities(event))
            }
        case "result":
            guard let id else { return }
            if id == subscriptionID {
                if message["success"]?.bool != true { log.error("subscribe_entities failed") }
                return
            }
            guard let cont = pending.removeValue(forKey: id) else { return }
            if message["success"]?.bool == true {
                cont.resume(returning: message["result"] ?? .null)
            } else {
                let err = message["error"]
                cont.resume(
                    throwing: HAClientError.serviceError(
                        code: err?["code"]?.string ?? "unknown", message: err?["message"]?.string ?? ""))
            }
        case "pong":
            lastPongAt = .now
        default:
            break
        }
    }

    private func allocateID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func send(_ value: JSONValue, on task: URLSessionWebSocketTask) async throws {
        let data = try value.serialized()
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func receive(_ task: URLSessionWebSocketTask, timeout: Duration?) async throws -> JSONValue {
        let timer: Task<Void, Never>? = timeout.map { t in
            Task {
                try? await Task.sleep(for: t)
                if !Task.isCancelled { task.cancel(with: .goingAway, reason: nil) }
            }
        }
        defer { timer?.cancel() }
        let message = try await task.receive()
        let data: Data
        switch message {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: throw HAClientError.protocolError("unknown frame")
        }
        return try JSONValue.parse(data)
    }

    private func failPending(_ error: Error) {
        let all = pending
        pending.removeAll()
        for (_, c) in all { c.resume(throwing: error) }
    }

    private func resolve(_ id: Int, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    // MARK: Subscription

    /// Changes which entities are subscribed, without dropping the connection.
    ///
    /// When connected, the old `subscribe_entities` subscription is cancelled and a new one is
    /// made; HA then sends a fresh snapshot of just these entities. Otherwise the list is kept
    /// for the next connect.
    public func updateSubscription(entityIDs ids: [String]) async {
        guard ids != entityIDs else { return }
        entityIDs = ids
        guard let task = socket, let oldID = subscriptionID else { return }
        let newID = allocateID()
        // Set first, so events for the old subscription are ignored from now on.
        subscriptionID = newID
        do {
            try await send(["id": .integer(newID), "type": "subscribe_entities", "entity_ids": .strings(ids)], on: task)
            _ = try? await command(["type": "unsubscribe_events", "subscription": .integer(oldID)], timeout: .seconds(5))
            log.info("Resubscribed to \(ids.count) entities")
        } catch {
            log.info("Resubscribe failed, reconnecting: \(error.localizedDescription, privacy: .public)")
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    // MARK: Commands

    /// Sends one WebSocket command (any `type`) and returns its `result`.
    ///
    /// `message` must not include `id`; it's added here.
    @discardableResult
    public func command(_ message: [String: JSONValue], timeout: Duration = .seconds(10)) async throws -> JSONValue {
        guard let task = socket, subscriptionID != nil else { throw HAClientError.notConnected }
        let id = allocateID()
        var message = message
        message["id"] = .integer(id)
        let payload = JSONValue.object(message)

        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            Task {
                do { try await self.send(payload, on: task) } catch { self.resolve(id, error) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                self.resolve(id, HAClientError.timeout)
            }
        }
    }

    /// Calls a service, e.g. `callService("switch", "toggle", entityIDs: ["switch.x"])`.
    @discardableResult
    public func callService(
        _ domain: String, _ service: String, entityIDs: [String] = [], data: [String: JSONValue] = [:]
    ) async throws -> JSONValue {
        var message: [String: JSONValue] = [
            "type": "call_service", "domain": .string(domain), "service": .string(service),
        ]
        if !entityIDs.isEmpty { message["target"] = ["entity_id": .strings(entityIDs)] }
        if !data.isEmpty { message["service_data"] = .object(data) }
        return try await command(message)
    }
}
