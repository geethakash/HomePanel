import Foundation
import Observation
import os

/// Live cache of entity states, observed by the UI.
@MainActor
@Observable
public final class EntityStore {
    public private(set) var states: [String: HAState] = [:]
    public var status: ConnectionStatus = .disconnected
    /// Entities whose optimistic update timed out without a confirming event (for an error shake).
    public private(set) var rolledBack: Set<String> = []

    /// Optimistic state overrides, set on tap and cleared by the next event for that entity.
    private var optimistic: [String: String] = [:]
    @ObservationIgnored private var optimisticTimers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "HAKit", category: "EntityStore")

    public init() {}

    /// The entity's state, with any optimistic override applied.
    public subscript(_ entityID: String) -> HAState? {
        guard var s = states[entityID] else { return nil }
        if let o = optimistic[entityID] { s.state = o }
        return s
    }

    public func apply(_ event: JSONValue) {
        let isFullSnapshot = event["a"] != nil
        let touched = CompressedStates.apply(event, to: &states)
        // Any event about an entity confirms (or overrides) its optimistic value.
        for id in (event["c"]?.object?.keys).map(Array.init) ?? [] {
            clearOptimistic(id)
        }
        // Entity IDs and states only (never attributes or tokens).
        if isFullSnapshot {
            log.notice("Received \(touched.count) states")
            for id in touched.sorted() {
                log.notice("snapshot \(id, privacy: .public) = \(self.states[id]?.state ?? "?", privacy: .public)")
            }
        } else {
            for id in touched {
                log.notice("\(id, privacy: .public) → \(self.states[id]?.state ?? "removed", privacy: .public)")
            }
        }
    }

    /// Shows `state` right away; rolls back after `timeout` if HA doesn't send an update.
    public func setOptimistic(_ entityID: String, state: String, timeout: Duration = .seconds(4)) {
        optimistic[entityID] = state
        rolledBack.remove(entityID)
        optimisticTimers[entityID]?.cancel()
        optimisticTimers[entityID] = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self else { return }
            if self.optimistic.removeValue(forKey: entityID) != nil {
                self.rolledBack.insert(entityID)
                self.log.info("Rolled back \(entityID, privacy: .public)")
            }
        }
    }

    public func clearOptimistic(_ entityID: String) {
        optimisticTimers.removeValue(forKey: entityID)?.cancel()
        optimistic[entityID] = nil
    }

    public func acknowledgeRollback(_ entityID: String) {
        rolledBack.remove(entityID)
    }

    public func removeAll() {
        states.removeAll()
        for t in optimisticTimers.values { t.cancel() }
        optimisticTimers.removeAll()
        optimistic.removeAll()
    }
}
