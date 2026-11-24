import Foundation

/// One Home Assistant entity state.
public struct HAState: Sendable, Hashable, Identifiable {
    public let entityID: String
    public var state: String
    public var attributes: [String: JSONValue]
    public var lastChanged: Date
    public var lastUpdated: Date

    public var id: String { entityID }

    public init(
        entityID: String, state: String, attributes: [String: JSONValue] = [:],
        lastChanged: Date = .distantPast, lastUpdated: Date? = nil
    ) {
        self.entityID = entityID
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated ?? lastChanged
    }

    /// Decodes the REST shape (`GET /api/states/<id>`).
    public init(rest json: JSONValue) throws {
        guard let id = json["entity_id"]?.string, let state = json["state"]?.string else {
            throw HARestError.invalidResponse
        }
        self.init(
            entityID: id,
            state: state,
            attributes: json["attributes"]?.object ?? [:],
            lastChanged: json["last_changed"]?.string.flatMap(HADate.parse) ?? .distantPast,
            lastUpdated: json["last_updated"]?.string.flatMap(HADate.parse)
        )
    }

    // MARK: Generic helpers

    public var domain: String { String(entityID.prefix { $0 != "." }) }
    public var isOn: Bool { state == "on" }
    public var isAvailable: Bool { state != "unavailable" && state != "unknown" }
    public var friendlyName: String? { attributes["friendly_name"]?.string }
    public var numericState: Double? { Double(state) }
    public var unit: String? { attributes["unit_of_measurement"]?.string }
    public var deviceClass: String? { attributes["device_class"]?.string }

    // MARK: Lights

    /// 0–100, or nil when the light is off / has no brightness.
    public var brightnessPct: Int? {
        attributes["brightness"]?.double.map { Int(($0 / 255 * 100).rounded()) }
    }

    public var rgb: [Int]? {
        guard let a = attributes["rgb_color"]?.array, a.count >= 3 else { return nil }
        let v = a.prefix(3).compactMap(\.int)
        return v.count == 3 ? v : nil
    }

    /// `supported_color_modes`, e.g. ["onoff"], ["brightness"], ["color_temp", "hs"].
    public var supportedColorModes: [String] {
        attributes["supported_color_modes"]?.array?.compactMap(\.string) ?? []
    }

    /// Dimmable. Lights that don't report color modes are assumed dimmable.
    public var supportsBrightness: Bool {
        let modes = supportedColorModes
        return modes.isEmpty || modes.contains { $0 != "onoff" }
    }

    public var supportsColor: Bool {
        let modes = supportedColorModes
        guard !modes.isEmpty else { return attributes["rgb_color"] != nil || attributes["hs_color"] != nil }
        return !Set(modes).isDisjoint(with: ["hs", "xy", "rgb", "rgbw", "rgbww"])
    }

    public var supportsColorTemp: Bool { supportedColorModes.contains("color_temp") }
    public var colorTempKelvin: Double? { attributes["color_temp_kelvin"]?.double }
    public var minColorTempKelvin: Double { attributes["min_color_temp_kelvin"]?.double ?? 2000 }
    public var maxColorTempKelvin: Double { attributes["max_color_temp_kelvin"]?.double ?? 6500 }
    /// The light's current color mode ("color_temp", "hs"…), nil when off.
    public var colorMode: String? { attributes["color_mode"]?.string }

    public var effect: String? { attributes["effect"]?.string }
    public var effectList: [String] { attributes["effect_list"]?.array?.compactMap(\.string) ?? [] }

    // MARK: Selects / numbers

    public var options: [String] { attributes["options"]?.array?.compactMap(\.string) ?? [] }
    public var minValue: Double? { attributes["min"]?.double }
    public var maxValue: Double? { attributes["max"]?.double }
    public var step: Double? { attributes["step"]?.double }

    // MARK: Climate

    public var temperature: Double? { attributes["temperature"]?.double }
    public var currentTemperature: Double? { attributes["current_temperature"]?.double }
    public var hvacModes: [String] { attributes["hvac_modes"]?.array?.compactMap(\.string) ?? [] }
    public var minTemp: Double? { attributes["min_temp"]?.double }
    public var maxTemp: Double? { attributes["max_temp"]?.double }
    public var targetTempStep: Double? { attributes["target_temp_step"]?.double }
    public var targetTempLow: Double? { attributes["target_temp_low"]?.double }
    public var targetTempHigh: Double? { attributes["target_temp_high"]?.double }
    /// What the unit is doing right now: "cooling", "heating", "idle"…
    public var hvacAction: String? { attributes["hvac_action"]?.string }
    public var fanModes: [String] { attributes["fan_modes"]?.array?.compactMap(\.string) ?? [] }
    public var fanMode: String? { attributes["fan_mode"]?.string }
    public var swingModes: [String] { attributes["swing_modes"]?.array?.compactMap(\.string) ?? [] }
    public var swingMode: String? { attributes["swing_mode"]?.string }
    public var swingHorizontalModes: [String] {
        attributes["swing_horizontal_modes"]?.array?.compactMap(\.string) ?? []
    }
    public var swingHorizontalMode: String? { attributes["swing_horizontal_mode"]?.string }
    public var presetModes: [String] { attributes["preset_modes"]?.array?.compactMap(\.string) ?? [] }
    public var presetMode: String? { attributes["preset_mode"]?.string }

    /// The `supported_features` bit mask.
    public var supportedFeatures: Int { attributes["supported_features"]?.int ?? 0 }

    // MARK: Timers

    public var finishesAt: Date? { attributes["finishes_at"]?.string.flatMap(HADate.parse) }
    /// Timer duration in seconds (attribute is "H:MM:SS").
    public var timerDuration: TimeInterval? { attributes["duration"]?.string.flatMap(HADate.parseDuration) }
}

/// Connection state shown in the panel header.
public enum ConnectionStatus: Sendable, Equatable {
    case needsSetup
    case disconnected
    case connecting
    case connected
    case reconnecting
    case notOnHomeNetwork
    case authFailed
    case error(String)

    public var isConnected: Bool { self == .connected }

    public var label: String {
        switch self {
        case .needsSetup: "Set up Home Assistant in Settings"
        case .disconnected: "Home Assistant · disconnected"
        case .connecting: "Connecting…"
        case .connected: "Home Assistant · connected"
        case .reconnecting: "Reconnecting…"
        case .notOnHomeNetwork: "Not on home network"
        case .authFailed: "Token rejected. Check Settings"
        case .error(let m): m
        }
    }
}

public enum HADate {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let lock = NSLock()

    public static func parse(_ s: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        if let d = fractional.date(from: s) { return d }
        if let d = plain.date(from: s) { return d }
        // HA sends microseconds (6 digits); trim to milliseconds and retry.
        if let dot = s.firstIndex(of: "."),
            let tz = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        {
            let frac = s[s.index(after: dot)..<tz].prefix(3)
            return fractional.date(from: String(s[..<dot]) + "." + frac + String(s[tz...]))
        }
        return nil
    }

    /// "0:15:00" → 900. Also accepts "15:00" and "1 day, 0:00:00".
    public static func parseDuration(_ s: String) -> TimeInterval? {
        var days = 0.0
        var rest = Substring(s)
        if let comma = s.firstIndex(of: ",") {
            days = Double(s[..<comma].split(separator: " ").first ?? "") ?? 0
            rest = s[s.index(after: comma)...].drop { $0 == " " }
        }
        let parts = rest.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        let secs = parts.reversed().enumerated().reduce(0.0) { $0 + $1.element * pow(60, Double($1.offset)) }
        return days * 86_400 + secs
    }

    /// 900 → "00:15:00" (the format `timer.start` expects).
    public static func formatDuration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

/// Decoder for `subscribe_entities` events, which use HA's compressed state format.
///
/// - `a`: full states `{entity_id: {s, a, lc, lu?}}`
/// - `c`: changes `{entity_id: {"+": {s?, a?, lc?, lu?}, "-": {a: [keys]}}}`
/// - `r`: removed entity IDs
public enum CompressedStates {
    /// Applies an event and returns the IDs of entities whose state *string* changed or
    /// that were added or removed (for logging).
    @discardableResult
    public static func apply(_ event: JSONValue, to states: inout [String: HAState]) -> [String] {
        var touched: [String] = []

        if let added = event["a"]?.object {
            for (id, c) in added {
                let lc = c["lc"]?.double.map(Date.init(timeIntervalSince1970:)) ?? .distantPast
                let lu = c["lu"]?.double.map(Date.init(timeIntervalSince1970:)) ?? lc
                states[id] = HAState(
                    entityID: id, state: c["s"]?.string ?? "unknown",
                    attributes: c["a"]?.object ?? [:], lastChanged: lc, lastUpdated: lu)
                touched.append(id)
            }
        }

        if let changes = event["c"]?.object {
            for (id, diff) in changes {
                guard var st = states[id] else { continue }
                let before = st.state
                if let plus = diff["+"] {
                    if let s = plus["s"]?.string { st.state = s }
                    if let attrs = plus["a"]?.object { st.attributes.merge(attrs) { _, new in new } }
                    if let lc = plus["lc"]?.double {
                        st.lastChanged = Date(timeIntervalSince1970: lc)
                        st.lastUpdated = st.lastChanged
                    }
                    if let lu = plus["lu"]?.double { st.lastUpdated = Date(timeIntervalSince1970: lu) }
                }
                if let removedKeys = diff["-"]?["a"]?.array?.compactMap(\.string) {
                    for k in removedKeys { st.attributes[k] = nil }
                }
                states[id] = st
                if st.state != before { touched.append(id) }
            }
        }

        if let removed = event["r"]?.array?.compactMap(\.string) {
            for id in removed {
                states[id] = nil
                touched.append(id)
            }
        }
        return touched
    }
}
