import Foundation

/// A Home Assistant Area (a room, usually).
public struct HAArea: Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    /// An `mdi:` icon name, if the area has one.
    public var icon: String?
    public var floorID: String?

    public init(id: String, name: String, icon: String? = nil, floorID: String? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.floorID = floorID
    }
}

/// A Home Assistant device (one physical thing, which owns several entities).
public struct HADevice: Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var areaID: String?
    public var manufacturer: String?
    public var model: String?

    public init(id: String, name: String, areaID: String? = nil, manufacturer: String? = nil, model: String? = nil) {
        self.id = id
        self.name = name
        self.areaID = areaID
        self.manufacturer = manufacturer
        self.model = model
    }
}

/// One entity, with the registry details the layout editor and generator need.
public struct CatalogEntity: Sendable, Hashable, Identifiable {
    public enum Category: String, Sendable, Hashable {
        case config, diagnostic
    }

    public let entityID: String
    public var name: String
    /// The entity's own area, or else its device's area.
    public var areaID: String?
    public var deviceID: String?
    /// The integration that provides it (e.g. "wled", "localtuya").
    public var platform: String?
    public var icon: String?
    public var category: Category?
    public var hidden: Bool

    public var id: String { entityID }
    public var domain: String { String(entityID.prefix { $0 != "." }) }
    /// Worth a card of its own: not hidden and not a config or diagnostic entity.
    public var isPrimary: Bool { category == nil && !hidden }

    public init(
        entityID: String, name: String, areaID: String? = nil, deviceID: String? = nil, platform: String? = nil,
        icon: String? = nil, category: Category? = nil, hidden: Bool = false
    ) {
        self.entityID = entityID
        self.name = name
        self.areaID = areaID
        self.deviceID = deviceID
        self.platform = platform
        self.icon = icon
        self.category = category
        self.hidden = hidden
    }
}

/// Everything in a Home Assistant install that the panel can show: areas, devices and entities.
///
/// Built from the registry lists and `get_states`; see `HARegistry.fetchCatalog`.
public struct EntityCatalog: Sendable {
    public private(set) var areas: [HAArea]
    public private(set) var devices: [String: HADevice]
    /// Every entity that has a state, sorted by name.
    public private(set) var entities: [CatalogEntity]
    public private(set) var states: [String: HAState]
    public var temperatureUnit: String
    public var haVersion: String?
    public var locationName: String?

    private var byID: [String: Int]

    public init(
        areas: [HAArea], devices: [HADevice], entities: [CatalogEntity], states: [HAState],
        temperatureUnit: String = "°C", haVersion: String? = nil, locationName: String? = nil
    ) {
        self.areas = areas.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.devices = Dictionary(devices.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.entities = entities.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.states = Dictionary(states.map { ($0.entityID, $0) }, uniquingKeysWith: { a, _ in a })
        self.temperatureUnit = temperatureUnit
        self.haVersion = haVersion
        self.locationName = locationName
        byID = Dictionary(self.entities.enumerated().map { ($1.entityID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Decoding HA replies

    /// Builds the catalog from the raw WebSocket results.
    ///
    /// - Parameters:
    ///   - areas: `config/area_registry/list`
    ///   - devices: `config/device_registry/list`
    ///   - entities: `config/entity_registry/list_for_display` (compact keys), or the admin-only
    ///     `config/entity_registry/list` (full keys)
    ///   - states: `get_states`
    ///   - config: `get_config`
    public init(areas: JSONValue, devices: JSONValue, entities: JSONValue, states: JSONValue, config: JSONValue = .null) {
        let areaList: [HAArea] = (areas.array ?? []).compactMap { a in
            guard let id = a["area_id"]?.string else { return nil }
            return HAArea(id: id, name: a["name"]?.string ?? id, icon: a["icon"]?.string, floorID: a["floor_id"]?.string)
        }
        let deviceList: [HADevice] = (devices.array ?? []).compactMap { d in
            guard let id = d["id"]?.string, d["disabled_by"]?.string == nil else { return nil }
            return HADevice(
                id: id,
                name: d["name_by_user"]?.string ?? d["name"]?.string ?? id,
                areaID: d["area_id"]?.string,
                manufacturer: d["manufacturer"]?.string,
                model: d["model"]?.string)
        }
        let deviceArea = Dictionary(deviceList.map { ($0.id, $0.areaID) }, uniquingKeysWith: { a, _ in a })

        let stateList: [HAState] = (states.array ?? []).compactMap { try? HAState(rest: $0) }
        let stateByID = Dictionary(stateList.map { ($0.entityID, $0) }, uniquingKeysWith: { a, _ in a })

        var catalogEntities: [String: CatalogEntity] = [:]
        for entry in Self.registryEntries(entities) {
            // Only entities HA is actually running (registry entries can outlive their integration).
            guard let state = stateByID[entry.entityID] else { continue }
            var e = entry
            e.areaID = entry.areaID ?? entry.deviceID.flatMap { deviceArea[$0] ?? nil }
            e.name = state.friendlyName ?? entry.name
            catalogEntities[e.entityID] = e
        }
        // Entities without a registry entry (e.g. YAML ones without a unique_id) have no area.
        for state in stateList where catalogEntities[state.entityID] == nil {
            catalogEntities[state.entityID] = CatalogEntity(
                entityID: state.entityID, name: state.friendlyName ?? state.entityID,
                icon: state.attributes["icon"]?.string)
        }

        self.init(
            areas: areaList, devices: deviceList, entities: Array(catalogEntities.values), states: stateList,
            temperatureUnit: config["unit_system"]?["temperature"]?.string ?? "°C",
            haVersion: config["version"]?.string,
            locationName: config["location_name"]?.string)
    }

    /// Reads either registry shape into entries (names are the registry name or the entity ID).
    static func registryEntries(_ json: JSONValue) -> [CatalogEntity] {
        // `list_for_display`: {"entity_categories": {"0": "config", …}, "entities": [{"ei", "ai", "di", …}]}
        if let compact = json["entities"]?.array {
            let categories = json["entity_categories"]?.object?.compactMapValues(\.string) ?? [:]
            return compact.compactMap { e in
                guard let id = e["ei"]?.string else { return nil }
                return CatalogEntity(
                    entityID: id,
                    name: e["en"]?.string ?? id,
                    areaID: e["ai"]?.string,
                    deviceID: e["di"]?.string,
                    platform: e["pl"]?.string,
                    icon: e["ic"]?.string,
                    category: e["ec"]?.int.flatMap { categories[String($0)] }.flatMap(CatalogEntity.Category.init),
                    hidden: e["hb"]?.bool ?? false)
            }
        }
        // `entity_registry/list`: [{"entity_id", "area_id", "device_id", "entity_category", "hidden_by", …}]
        return (json.array ?? []).compactMap { e in
            guard let id = e["entity_id"]?.string, e["disabled_by"]?.string == nil else { return nil }
            return CatalogEntity(
                entityID: id,
                name: e["name"]?.string ?? e["original_name"]?.string ?? id,
                areaID: e["area_id"]?.string,
                deviceID: e["device_id"]?.string,
                platform: e["platform"]?.string,
                icon: e["icon"]?.string ?? e["original_icon"]?.string,
                category: e["entity_category"]?.string.flatMap(CatalogEntity.Category.init),
                hidden: e["hidden_by"]?.string != nil)
        }
    }

    // MARK: Queries

    public func entity(_ entityID: String) -> CatalogEntity? {
        byID[entityID].map { entities[$0] }
    }

    public func area(_ areaID: String) -> HAArea? {
        areas.first { $0.id == areaID }
    }

    /// Entities in an area. `primaryOnly` skips hidden, config and diagnostic entities.
    public func entities(inArea areaID: String?, primaryOnly: Bool = true) -> [CatalogEntity] {
        entities.filter { $0.areaID == areaID && (!primaryOnly || $0.isPrimary) }
    }

    /// All entities of a device, including config and diagnostic ones (candidates for attachments).
    public func entities(ofDevice deviceID: String) -> [CatalogEntity] {
        entities.filter { $0.deviceID == deviceID }
    }

    /// Entities matching `query` (name or entity ID), optionally limited to an area and domains.
    public func search(
        _ query: String, area: String? = nil, domains: Set<String>? = nil, primaryOnly: Bool = false
    ) -> [CatalogEntity] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return entities.filter { e in
            if let area, e.areaID != area { return false }
            if let domains, !domains.contains(e.domain) { return false }
            if primaryOnly, !e.isPrimary { return false }
            guard !q.isEmpty else { return true }
            return e.name.localizedStandardContains(q) || e.entityID.localizedStandardContains(q)
        }
    }

    /// Number of primary entities per area ID (nil = no area), for "Kitchen · 12 devices".
    public var primaryCountByArea: [String?: Int] {
        entities.reduce(into: [:]) { counts, e in
            if e.isPrimary { counts[e.areaID, default: 0] += 1 }
        }
    }
}
