import Foundation

/// Builds a room from a Home Assistant Area: sections by device type, related entities of the
/// same device attached to their main card, and the area's temperature and humidity as header
/// readings.
public enum LayoutGenerator {
    /// Domains that never get a card of their own.
    public static let skippedDomains: Set<String> = [
        "automation", "camera", "conversation", "device_tracker", "event", "image", "notify", "person", "remote",
        "stt", "sun", "todo", "tts", "update", "wake_word", "weather", "zone", "calendar", "text", "date", "time",
        "datetime", "input_text", "input_datetime", "tag", "assist_satellite", "ai_task", "vacuum", "water_heater",
        "valve", "lawn_mower", "timer", "counter", "schedule", "select", "number",
    ]

    /// Section order, titles and styles.
    static let sections: [(title: String, style: CardSection.Style, kinds: Set<Card.Kind>)] = [
        ("Lights", .grid, [.light]),
        ("Climate", .rows, [.climate]),
        ("Switches", .grid, [.toggle]),
        ("Covers", .grid, [.cover]),
        ("Fans", .grid, [.fan]),
        ("Media", .grid, [.media]),
        ("Security", .grid, [.lock, .alarm]),
        ("Sensors", .grid, [.sensor, .binarySensor]),
        ("Controls", .grid, [.select, .number]),
        ("Scenes", .pills, [.scene, .script, .button]),
    ]

    /// Sensor device classes worth a tile (batteries, signal strength and the like are left out).
    static let usefulSensorClasses: Set<String> = [
        "temperature", "humidity", "carbon_dioxide", "pm25", "pm10", "aqi", "illuminance", "power", "pressure",
        "volatile_organic_compounds", "carbon_monoxide",
    ]
    static let usefulBinaryClasses: Set<String> = [
        "door", "garage_door", "window", "opening", "motion", "occupancy", "presence", "moisture", "smoke", "gas",
        "carbon_monoxide", "lock", "safety", "problem", "vibration", "sound",
    ]
    static let maxSensors = 9

    /// A room for `areaID` (nil = entities with no area, named "Other").
    public static func room(for areaID: String?, in catalog: EntityCatalog) -> Room {
        let area = areaID.flatMap(catalog.area)
        let name = area?.name ?? "Other"
        let candidates = catalog.entities(inArea: areaID)
            .filter { !skippedDomains.contains($0.domain) || isInputControl($0) }
            .filter { isUseful($0, catalog) }

        // Main entity per device gets the device's selects, numbers and switches attached.
        var attachedIDs = Set<String>()
        var cards: [Card] = []
        for entity in candidates.sorted(by: { hostRank($0) < hostRank($1) }) {
            guard !attachedIDs.contains(entity.entityID) else { continue }
            var card = Card(entityID: entity.entityID, kind: Card.Kind.forEntity(entity.entityID))
            if let deviceID = entity.deviceID {
                let siblings = catalog.entities(ofDevice: deviceID).filter { $0.entityID != entity.entityID }
                card.attachments = attachments(for: card, siblings: siblings, device: catalog.devices[deviceID], catalog)
                attachedIDs.formUnion(card.attachments.map(\.entityID))
            }
            cards.append(card)
        }
        // Keep catalog order (by name) within each section, minus anything that became an attachment.
        let order = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { ($1.entityID, $0) })
        cards = cards.filter { !attachedIDs.contains($0.entityID) }
            .sorted { (order[$0.entityID] ?? 0) < (order[$1.entityID] ?? 0) }

        var built: [CardSection] = []
        for spec in sections {
            var inSection = cards.filter { spec.kinds.contains($0.kind) }
            if spec.kinds.contains(.sensor) { inSection = Array(inSection.prefix(maxSensors)) }
            if !inSection.isEmpty { built.append(CardSection(title: spec.title, style: spec.style, cards: inSection)) }
        }

        return Room(
            name: name, icon: icon(for: area), areaID: areaID,
            headerSensors: headerSensors(areaID, catalog), sections: built)
    }

    /// A card for one entity, with related entities of its device attached (for "Add device").
    public static func card(for entityID: String, in catalog: EntityCatalog) -> Card {
        var card = Card(entityID: entityID)
        if let entity = catalog.entity(entityID), let deviceID = entity.deviceID {
            let siblings = catalog.entities(ofDevice: deviceID).filter { $0.entityID != entityID }
            card.attachments = attachments(for: card, siblings: siblings, device: catalog.devices[deviceID], catalog)
        }
        return card
    }

    // MARK: Attachments

    /// Related entities of the same device, with roles guessed from their names.
    static func attachments(
        for card: Card, siblings: [CatalogEntity], device: HADevice?, _ catalog: EntityCatalog
    ) -> [Attachment] {
        let usable = siblings.filter { $0.category != .diagnostic && !$0.hidden }
        var result: [Attachment] = []
        func words(_ e: CatalogEntity) -> String {
            (e.name + " " + e.entityID).lowercased().replacingOccurrences(of: "_", with: " ")
        }
        switch card.kind {
        case .light:
            for e in usable {
                let w = words(e)
                if e.domain == "select", w.contains("preset") {
                    result.append(Attachment(e.entityID, role: .preset))
                } else if e.domain == "number", w.contains("speed") {
                    result.append(Attachment(e.entityID, role: .speed))
                }
            }
        case .climate:
            for e in usable {
                let w = words(e)
                if e.domain == "select" {
                    if let role = climateSelectRole(w) { result.append(Attachment(e.entityID, role: role)) }
                } else if e.domain == "switch" {
                    let short = shortName(e.name, device: device)
                    result.append(Attachment(e.entityID, role: .feature, name: short, icon: featureIcon(w)))
                }
            }
        case .toggle:
            for e in usable where e.domain == "select" {
                let w = words(e)
                if w.contains("power on") || w.contains("power-on") || w.contains("restore") || w.contains("relay status")
                    || w.contains("power outage")
                {
                    result.append(Attachment(e.entityID, role: .powerOnBehaviour))
                }
            }
        default:
            break
        }
        // One of each single-value role.
        var seen = Set<Attachment.Role>()
        return result.filter { $0.role == .feature || seen.insert($0.role).inserted }
    }

    public static func climateSelectRole(_ w: String) -> Attachment.Role? {
        let isFlow = w.contains("flow") || w.contains("swing") || w.contains("louver") || w.contains("louvre")
            || w.contains("vane") || w.contains("direction")
        if isFlow && (w.contains("left") || w.contains("right") || w.contains("horizontal")) { return .swingHorizontal }
        if isFlow { return .swingVertical }
        if w.contains("fan") { return .fanSpeed }
        if w.contains("sleep") { return .sleep }
        if w.contains("gen") || w.contains("power limit") || w.contains("power level") { return .powerLimit }
        return nil
    }

    static func featureIcon(_ w: String) -> String {
        if w.contains("eco") { return "leaf" }
        if w.contains("health") || w.contains("ion") || w.contains("plasma") { return "heart" }
        if w.contains("soft") || w.contains("wind") { return "wind" }
        if w.contains("mildew") || w.contains("clean") || w.contains("dry") { return "drop.degreesign.slash" }
        if w.contains("display") || w.contains("light") || w.contains("led") { return "light.max" }
        if w.contains("buzzer") || w.contains("beep") || w.contains("sound") { return "speaker.wave.2" }
        if w.contains("turbo") || w.contains("boost") { return "hare" }
        if w.contains("sleep") { return "moon" }
        return "switch.2"
    }

    /// "Room AC Eco" on device "Room AC" → "Eco".
    static func shortName(_ name: String, device: HADevice?) -> String {
        guard let device, name.lowercased().hasPrefix(device.name.lowercased()) else { return name }
        let rest = name.dropFirst(device.name.count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? name : rest.prefix(1).uppercased() + rest.dropFirst()
    }

    // MARK: Filters and ranking

    /// Which entity of a device is the main card: climate before light before fan…
    static func hostRank(_ e: CatalogEntity) -> Int {
        ["climate", "light", "fan", "cover", "media_player", "lock", "alarm_control_panel", "switch"]
            .firstIndex(of: e.domain) ?? 99
    }

    static func isInputControl(_ e: CatalogEntity) -> Bool {
        e.domain == "input_select" || e.domain == "input_number"
    }

    static func isUseful(_ e: CatalogEntity, _ catalog: EntityCatalog) -> Bool {
        let deviceClass = catalog.states[e.entityID]?.deviceClass
        switch e.domain {
        case "sensor": return deviceClass.map(usefulSensorClasses.contains) ?? false
        case "binary_sensor": return deviceClass.map(usefulBinaryClasses.contains) ?? false
        default: return true
        }
    }

    static func headerSensors(_ areaID: String?, _ catalog: EntityCatalog) -> [String] {
        let sensors = catalog.entities(inArea: areaID).filter { $0.domain == "sensor" }
        func first(_ deviceClass: String) -> String? {
            sensors.first { catalog.states[$0.entityID]?.deviceClass == deviceClass }?.entityID
        }
        return [first("temperature"), first("humidity")].compactMap { $0 }
    }

    // MARK: Room icon

    /// An SF Symbol for the area, from its `mdi:` icon or its name.
    public static func icon(for area: HAArea?) -> String {
        let text = ((area?.icon ?? "") + " " + (area?.name ?? "")).lowercased()
        let rules: [(keys: [String], symbol: String)] = [
            (["bed", "sleep"], "bed.double"),
            (["sofa", "living", "lounge", "couch", "family"], "sofa"),
            (["kitchen", "fridge", "silverware", "food", "dining"], "fork.knife"),
            (["bath", "shower", "toilet", "washroom", "restroom"], "shower"),
            (["office", "desk", "study", "monitor", "work"], "desktopcomputer"),
            (["garage", "car"], "car"),
            (["garden", "yard", "flower", "tree", "outdoor", "patio", "balcony", "terrace"], "leaf"),
            (["laundry", "washing"], "washer"),
            (["stair", "hall", "entrance", "door", "corridor", "foyer"], "door.left.hand.closed"),
            (["kid", "child", "nursery", "baby", "toy"], "teddybear"),
            (["gym", "dumbbell", "fitness"], "dumbbell"),
            (["tv", "media", "theater", "theatre", "cinema"], "tv"),
            (["guest"], "person.2"),
        ]
        return rules.first { rule in rule.keys.contains { text.contains($0) } }?.symbol ?? "house"
    }
}
