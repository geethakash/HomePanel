import Foundation

/// The user's panel layout: rooms, sections and device cards. Saved as JSON.
public struct PanelConfig: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var rooms: [Room]
    public var lastRoomID: UUID?

    public init(rooms: [Room] = [], lastRoomID: UUID? = nil) {
        self.version = Self.currentVersion
        self.rooms = rooms
        self.lastRoomID = lastRoomID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        rooms = try c.decodeIfPresent([Room].self, forKey: .rooms) ?? []
        lastRoomID = try c.decodeIfPresent(UUID.self, forKey: .lastRoomID)
    }

    public func room(_ id: UUID?) -> Room? {
        rooms.first { $0.id == id } ?? rooms.first
    }

    /// Finds a card and the section that holds it, in any room.
    public func locate(card id: UUID) -> (room: Room, section: CardSection, card: Card)? {
        for room in rooms {
            for section in room.sections {
                if let card = section.cards.first(where: { $0.id == id }) { return (room, section, card) }
            }
        }
        return nil
    }

    /// Every entity a room needs live: its cards, their attachments and its header sensors.
    public static func entityIDs(in room: Room) -> [String] {
        var ids: [String] = room.headerSensors
        for section in room.sections {
            for card in section.cards {
                ids.append(card.entityID)
                ids += card.attachments.map(\.entityID)
            }
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    public var allEntityIDs: [String] {
        var seen = Set<String>()
        return rooms.flatMap(Self.entityIDs(in:)).filter { seen.insert($0).inserted }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> PanelConfig {
        try JSONDecoder().decode(PanelConfig.self, from: data)
    }
}

public struct Room: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var icon: String
    /// HA area this room was built from, if any.
    public var areaID: String?
    /// Read-only sensors shown at the top right of the header (e.g. temperature, humidity).
    public var headerSensors: [String]
    public var sections: [CardSection]

    public init(
        id: UUID = UUID(), name: String, icon: String = "house", areaID: String? = nil,
        headerSensors: [String] = [], sections: [CardSection] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.areaID = areaID
        self.headerSensors = headerSensors
        self.sections = sections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "house"
        areaID = try c.decodeIfPresent(String.self, forKey: .areaID)
        headerSensors = try c.decodeIfPresent([String].self, forKey: .headerSensors) ?? []
        sections = try c.decodeIfPresent([CardSection].self, forKey: .sections) ?? []
    }
}

public struct CardSection: Codable, Sendable, Equatable, Identifiable {
    public enum Style: String, Codable, Sendable, CaseIterable {
        /// Square tiles, three per row.
        case grid
        /// Full-width rows (climate, media).
        case rows
        /// Small pills (scenes, scripts).
        case pills
    }

    public var id: UUID
    public var title: String
    public var style: Style
    public var cards: [Card]

    public init(id: UUID = UUID(), title: String, style: Style = .grid, cards: [Card] = []) {
        self.id = id
        self.title = title
        self.style = style
        self.cards = cards
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        style = try c.decodeIfPresent(Style.self, forKey: .style) ?? .grid
        cards = try c.decodeIfPresent([Card].self, forKey: .cards) ?? []
    }

    public var visibleCards: [Card] { cards.filter { !$0.hidden } }
}

/// One device in the panel.
public struct Card: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var entityID: String
    public var kind: Kind
    /// Overrides HA's friendly name.
    public var name: String?
    /// SF Symbol; nil uses the kind's default.
    public var icon: String?
    public var hidden: Bool
    /// Related entities shown on the device screen (presets, speed, A/C selects…).
    public var attachments: [Attachment]

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case toggle, light, climate, cover, fan, media, lock, alarm
        case sensor, binarySensor, scene, script, button, select, number

        /// The natural kind for an entity's domain.
        public static func forEntity(_ entityID: String) -> Kind {
            switch String(entityID.prefix { $0 != "." }) {
            case "light": .light
            case "climate": .climate
            case "cover": .cover
            case "fan": .fan
            case "media_player": .media
            case "lock": .lock
            case "alarm_control_panel": .alarm
            case "sensor": .sensor
            case "binary_sensor": .binarySensor
            case "scene": .scene
            case "script": .script
            case "button", "input_button": .button
            case "select", "input_select": .select
            case "number", "input_number": .number
            default: .toggle  // switch, input_boolean, automation, siren…
            }
        }

        public var defaultIcon: String {
            switch self {
            case .toggle: "lightbulb"
            case .light: "lightbulb"
            case .climate: "thermometer.medium"
            case .cover: "blinds.vertical.closed"
            case .fan: "fan"
            case .media: "play.rectangle"
            case .lock: "lock"
            case .alarm: "shield"
            case .sensor: "gauge.with.dots.needle.33percent"
            case .binarySensor: "circle.dotted"
            case .scene: "sparkles"
            case .script: "scroll"
            case .button: "button.programmable"
            case .select: "list.bullet"
            case .number: "slider.horizontal.3"
            }
        }
    }

    public init(
        id: UUID = UUID(), entityID: String, kind: Kind? = nil, name: String? = nil, icon: String? = nil,
        hidden: Bool = false, attachments: [Attachment] = []
    ) {
        self.id = id
        self.entityID = entityID
        self.kind = kind ?? Kind.forEntity(entityID)
        self.name = name
        self.icon = icon
        self.hidden = hidden
        self.attachments = attachments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        entityID = try c.decode(String.self, forKey: .entityID)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? Kind.forEntity(entityID)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }

    public var displayIcon: String { icon ?? kind.defaultIcon }

    /// The first attachment with this role.
    public func attachment(_ role: Attachment.Role) -> Attachment? {
        attachments.first { $0.role == role }
    }

    public func attachments(_ role: Attachment.Role) -> [Attachment] {
        attachments.filter { $0.role == role }
    }
}

/// A related entity shown on a card's device screen.
public struct Attachment: Codable, Sendable, Equatable, Hashable {
    public enum Role: String, Codable, Sendable, CaseIterable {
        /// Light: preset select. Light: effect speed number.
        case preset, speed
        /// Climate: fan speed select (used instead of the climate entity's fan_mode).
        case fanSpeed
        /// Climate: vertical / horizontal air flow selects.
        case swingVertical, swingHorizontal
        /// Climate: sleep curve select, power limit select.
        case sleep, powerLimit
        /// Climate: on/off feature switch (Eco, Health, Display…).
        case feature
        /// Switch: HA timer helper for "Turn off after", power-on behaviour select.
        case offTimer, powerOnBehaviour
        /// Anything else, shown as a plain control.
        case generic
    }

    public var entityID: String
    public var role: Role
    public var name: String?
    public var icon: String?

    public init(_ entityID: String, role: Role, name: String? = nil, icon: String? = nil) {
        self.entityID = entityID
        self.role = role
        self.name = name
        self.icon = icon
    }
}
