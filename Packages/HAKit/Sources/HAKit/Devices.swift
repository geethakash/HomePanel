import Foundation

// MARK: - Supported features (HA's `supported_features` bits)

public struct CoverFeatures: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let open = Self(rawValue: 1)
    public static let close = Self(rawValue: 2)
    public static let setPosition = Self(rawValue: 4)
    public static let stop = Self(rawValue: 8)
    public static let openTilt = Self(rawValue: 16)
    public static let closeTilt = Self(rawValue: 32)
    public static let stopTilt = Self(rawValue: 64)
    public static let setTiltPosition = Self(rawValue: 128)
}

public struct FanFeatures: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let setSpeed = Self(rawValue: 1)
    public static let oscillate = Self(rawValue: 2)
    public static let direction = Self(rawValue: 4)
    public static let presetMode = Self(rawValue: 8)
}

public struct MediaFeatures: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let pause = Self(rawValue: 1)
    public static let seek = Self(rawValue: 2)
    public static let volumeSet = Self(rawValue: 4)
    public static let volumeMute = Self(rawValue: 8)
    public static let previousTrack = Self(rawValue: 16)
    public static let nextTrack = Self(rawValue: 32)
    public static let turnOn = Self(rawValue: 128)
    public static let turnOff = Self(rawValue: 256)
    public static let volumeStep = Self(rawValue: 1024)
    public static let selectSource = Self(rawValue: 2048)
    public static let stop = Self(rawValue: 4096)
    public static let play = Self(rawValue: 16384)
    public static let shuffleSet = Self(rawValue: 32768)
    public static let selectSoundMode = Self(rawValue: 65536)
}

public struct LockFeatures: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let open = Self(rawValue: 1)
}

public struct AlarmFeatures: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let armHome = Self(rawValue: 1)
    public static let armAway = Self(rawValue: 2)
    public static let armNight = Self(rawValue: 4)
    public static let trigger = Self(rawValue: 8)
    public static let armCustomBypass = Self(rawValue: 16)
    public static let armVacation = Self(rawValue: 32)
}

// MARK: - Attributes

extension HAState {
    public var coverFeatures: CoverFeatures { CoverFeatures(rawValue: supportedFeatures) }
    public var fanFeatures: FanFeatures { FanFeatures(rawValue: supportedFeatures) }
    public var mediaFeatures: MediaFeatures { MediaFeatures(rawValue: supportedFeatures) }
    public var lockFeatures: LockFeatures { LockFeatures(rawValue: supportedFeatures) }
    public var alarmFeatures: AlarmFeatures { AlarmFeatures(rawValue: supportedFeatures) }

    // Covers: 0 = closed, 100 = open.
    public var coverPosition: Int? { attributes["current_position"]?.int }
    public var coverTilt: Int? { attributes["current_tilt_position"]?.int }

    // Fans
    public var fanPercentage: Int? { attributes["percentage"]?.int }
    public var fanPercentageStep: Double { attributes["percentage_step"]?.double ?? 1 }
    public var oscillating: Bool? { attributes["oscillating"]?.bool }
    public var fanDirection: String? { attributes["direction"]?.string }

    // Media players
    public var mediaTitle: String? { attributes["media_title"]?.string }
    public var mediaArtist: String? { attributes["media_artist"]?.string ?? attributes["media_album_artist"]?.string }
    public var mediaAlbum: String? { attributes["media_album_name"]?.string }
    public var mediaAppName: String? { attributes["app_name"]?.string }
    /// Artwork path (relative to the HA URL, already signed) or a full URL.
    public var entityPicture: String? { attributes["entity_picture"]?.string }
    public var volumeLevel: Double? { attributes["volume_level"]?.double }
    public var isVolumeMuted: Bool { attributes["is_volume_muted"]?.bool ?? false }
    public var mediaSource: String? { attributes["source"]?.string }
    public var sourceList: [String] { attributes["source_list"]?.array?.compactMap(\.string) ?? [] }
    public var mediaDuration: Double? { attributes["media_duration"]?.double }
    public var mediaPosition: Double? { attributes["media_position"]?.double }
    public var mediaPositionUpdatedAt: Date? { attributes["media_position_updated_at"]?.string.flatMap(HADate.parse) }

    /// Where playback is now, counting time since HA last reported it.
    public func mediaPosition(at now: Date) -> Double? {
        guard let position = mediaPosition else { return nil }
        guard state == "playing", let updated = mediaPositionUpdatedAt else { return position }
        let p = position + now.timeIntervalSince(updated)
        return mediaDuration.map { min($0, p) } ?? p
    }

    // Locks and alarms
    /// "number" or a regex for text codes; nil when no code is needed.
    public var codeFormat: String? { attributes["code_format"]?.string }
    /// Alarms: whether arming needs the code too (HA's default is yes).
    public var codeArmRequired: Bool { attributes["code_arm_required"]?.bool ?? true }
    public var changedBy: String? { attributes["changed_by"]?.string }
}

// MARK: - State wording

/// Short, human state text for tiles and screens ("Open · 40%", "Armed away", "Detected").
public enum DeviceText {
    public static func summary(_ s: HAState) -> String {
        guard s.isAvailable else { return "Unavailable" }
        switch s.domain {
        case "cover": return cover(s)
        case "fan":
            guard s.isOn else { return "Off" }
            if let p = s.fanPercentage, p > 0 { return "On · \(p)%" }
            return s.presetMode.map { "On · \(label($0))" } ?? "On"
        case "media_player": return media(s)
        case "lock": return label(s.state)
        case "alarm_control_panel": return alarm(s.state)
        case "binary_sensor": return binarySensor(s)
        case "sensor", "input_number", "number", "counter": return value(s)
        case "select", "input_select": return s.state
        case "scene", "script", "button", "input_button":
            return s.domain == "script" && s.isOn ? "Running" : "Tap to run"
        default: return s.isOn ? "On" : (s.state == "off" ? "Off" : label(s.state))
        }
    }

    static func cover(_ s: HAState) -> String {
        switch s.state {
        case "open":
            if let p = s.coverPosition, p < 100 { return "Open · \(p)%" }
            return "Open"
        case "closed": return "Closed"
        case "opening": return "Opening…"
        case "closing": return "Closing…"
        default: return label(s.state)
        }
    }

    static func media(_ s: HAState) -> String {
        let status: String =
            switch s.state {
            case "playing": "Playing"
            case "paused": "Paused"
            case "idle", "standby": "Idle"
            case "buffering": "Buffering"
            case "on": "On"
            case "off": "Off"
            default: label(s.state)
            }
        guard s.state == "playing" || s.state == "paused" else { return status }
        if let title = s.mediaTitle, !title.isEmpty { return "\(status) · \(title)" }
        if let app = s.mediaAppName { return "\(status) · \(app)" }
        return status
    }

    public static func alarm(_ state: String) -> String {
        switch state {
        case "armed_home": "Armed home"
        case "armed_away": "Armed away"
        case "armed_night": "Armed night"
        case "armed_vacation": "Armed vacation"
        case "armed_custom_bypass": "Armed custom"
        case "disarmed": "Disarmed"
        case "arming": "Arming…"
        case "disarming": "Disarming…"
        case "pending": "Pending…"
        case "triggered": "Triggered"
        default: label(state)
        }
    }

    /// Words for "on" / "off" by device class (on = open, detected, wet…).
    public static func binarySensor(_ s: HAState) -> String {
        let on = s.isOn
        switch s.deviceClass {
        case "door", "garage_door", "opening", "window": return on ? "Open" : "Closed"
        case "motion", "occupancy", "presence", "moving", "vibration", "sound", "smoke", "gas", "carbon_monoxide",
            "tamper":
            return on ? "Detected" : "Clear"
        case "moisture": return on ? "Wet" : "Dry"
        case "problem": return on ? "Problem" : "OK"
        case "safety": return on ? "Unsafe" : "Safe"
        case "battery": return on ? "Low" : "Normal"
        case "battery_charging": return on ? "Charging" : "Not charging"
        case "connectivity": return on ? "Connected" : "Disconnected"
        case "lock": return on ? "Unlocked" : "Locked"
        case "plug": return on ? "Plugged in" : "Unplugged"
        case "light": return on ? "Light" : "Dark"
        case "running": return on ? "Running" : "Not running"
        case "update": return on ? "Update available" : "Up to date"
        case "heat": return on ? "Hot" : "Normal"
        case "cold": return on ? "Cold" : "Normal"
        default: return on ? "On" : "Off"
        }
    }

    /// "21.5 °C", "48%", "On battery"…
    public static func value(_ s: HAState) -> String {
        if let v = s.numericState {
            let unit = s.unit ?? ""
            let number =
                abs(v) >= 100 || v == v.rounded()
                ? v.formatted(.number.precision(.fractionLength(0)))
                : v.formatted(.number.precision(.fractionLength(0...1)))
            if unit.isEmpty { return number }
            return unit == "%" || unit.hasPrefix("°") ? number + unit : "\(number) \(unit)"
        }
        if s.deviceClass == "timestamp", let date = HADate.parse(s.state) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return label(s.state)
    }

    /// "armed_away" → "Armed away", "unlocked" → "Unlocked".
    public static func label(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalizedFirst
    }

    /// Whether the tile should look "on": open covers, running fans, playing media, unlocked locks,
    /// armed alarms and binary sensors that are on.
    public static func isActive(_ s: HAState) -> Bool {
        guard s.isAvailable else { return false }
        switch s.domain {
        case "cover": return s.state == "open" || s.state == "opening" || s.state == "closing"
        case "media_player": return !["off", "idle", "standby", "unknown"].contains(s.state)
        case "lock": return s.state != "locked"
        case "alarm_control_panel": return s.state != "disarmed"
        case "sensor", "number", "input_number", "select", "input_select", "scene", "button", "input_button",
            "counter":
            return false
        default: return s.isOn
        }
    }
}
