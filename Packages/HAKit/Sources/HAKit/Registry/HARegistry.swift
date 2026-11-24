import Foundation
import os

/// Reads Home Assistant's area, device and entity registries over the WebSocket connection.
public enum HARegistry {
    private static let log = Logger(subsystem: "HAKit", category: "HARegistry")

    /// Fetches areas, devices, entities, states and the core config, and builds the catalog.
    ///
    /// Works for non-admin users: it uses `entity_registry/list_for_display`, and falls back to the
    /// admin-only `entity_registry/list` only on old HA versions that lack it.
    public static func fetchCatalog(_ client: HAClient) async throws -> EntityCatalog {
        let big = Duration.seconds(30)
        async let areas = client.command(["type": "config/area_registry/list"], timeout: big)
        async let devices = client.command(["type": "config/device_registry/list"], timeout: big)
        async let entities = entityRegistry(client, timeout: big)
        async let states = client.command(["type": "get_states"], timeout: big)
        async let config = client.command(["type": "get_config"], timeout: big)

        let catalog = try await EntityCatalog(
            areas: areas, devices: devices, entities: entities, states: states, config: config)
        log.notice(
            "Catalog: \(catalog.areas.count) areas, \(catalog.devices.count) devices, \(catalog.entities.count) entities (\(catalog.entities.filter(\.isPrimary).count) primary)"
        )
        let byDomain = Dictionary(grouping: catalog.entities.filter(\.isPrimary), by: \.domain)
        let counts = byDomain.map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ")
        log.notice("Catalog domains: \(counts, privacy: .public)")
        return catalog
    }

    private static func entityRegistry(_ client: HAClient, timeout: Duration) async throws -> JSONValue {
        do {
            return try await client.command(["type": "config/entity_registry/list_for_display"], timeout: timeout)
        } catch HAClientError.serviceError(let code, _) where code == "unknown_command" {
            return try await client.command(["type": "config/entity_registry/list"], timeout: timeout)
        }
    }
}
