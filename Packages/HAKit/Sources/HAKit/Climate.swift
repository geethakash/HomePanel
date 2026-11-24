import Foundation

/// Friendly names and colors for HVAC modes.
public enum HVACMode {
    /// Display order for mode pickers; modes not listed here go last.
    public static let order = ["cool", "dry", "fan_only", "heat", "heat_cool", "auto"]

    public static func name(_ mode: String) -> String {
        switch mode {
        case "cool": "Cool"
        case "heat": "Heat"
        case "dry": "Dry"
        case "fan_only": "Fan"
        case "heat_cool": "Heat/Cool"
        case "auto": "Auto"
        case "off": "Off"
        default: mode.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// SF Symbol for the mode.
    public static func symbol(_ mode: String) -> String {
        switch mode {
        case "cool": "snowflake"
        case "heat": "sun.max.fill"
        case "dry": "drop.fill"
        case "fan_only": "fan.fill"
        case "auto", "heat_cool": "arrow.triangle.2.circlepath"
        default: "power"
        }
    }

    /// Mode color as 0xRRGGBB (nil = off, grey, no glow).
    public static func hex(_ mode: String) -> UInt32? {
        switch mode {
        case "cool": 0x64D2FF
        case "dry": 0x5AC8FA
        case "fan_only": 0xD1D6E0
        case "heat": 0xFF9F0A
        case "auto", "heat_cool": 0x30D158
        default: nil
        }
    }

    /// The unit's modes (without "off") in display order.
    public static func sorted(_ modes: [String]) -> [String] {
        let on = modes.filter { $0 != "off" }
        return on.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
    }

    /// "cooling" → "Cooling", for the `hvac_action` attribute.
    public static func actionName(_ action: String) -> String? {
        switch action {
        case "off", "": nil
        case "fan": "Fan"
        default: action.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// Maps air-flow option names (from a select or the climate's swing modes) to louver positions,
/// using keywords rather than exact names, so any A/C's options can drive the animation.
public enum Airflow {
    public enum Axis: Sendable { case vertical, horizontal }

    /// Which part of the range a swing option sweeps.
    public enum Region: Sendable, Equatable { case full, first, middle, last }

    public enum Position: Sendable, Equatable {
        /// Sweeping over a region (first = up / left, last = down / right).
        case sweep(Region)
        /// Held at a position from −1 (up / left) to 1 (down / right).
        case fixed(Double)

        public var isSweep: Bool {
            if case .sweep = self { return true }
            return false
        }
    }

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static let firstWords: Set = ["up", "top", "left", "high", "upper"]
    private static let lastWords: Set = ["down", "bottom", "right", "low", "lower"]
    private static let middleWords: Set = ["middle", "mid", "center", "centre"]

    /// True for options that sweep the louver, e.g. "Up-Down Flow", "swing", "on", "both".
    public static func isSweep(_ value: String, axis: Axis? = nil) -> Bool {
        let t = Set(tokens(value))
        if !t.isDisjoint(with: ["flow", "swing", "swinging", "sweep", "oscillate", "oscillating", "auto", "both", "on", "3d"]) {
            return true
        }
        switch axis {
        case .vertical: return t.contains("vertical") || t.contains("updown")
        case .horizontal: return t.contains("horizontal") || t.contains("leftright")
        case nil: return t.contains("vertical") || t.contains("horizontal")
        }
    }

    /// True for "off", "none", "stop" and the like.
    public static func isOff(_ value: String?) -> Bool {
        guard let value else { return true }
        return ["off", "none", "stop", "stopped", "unknown", "unavailable", "", "0"].contains(value.lowercased())
    }

    /// Where `value` puts the louver, given the full list of options it came from.
    ///
    /// Swing options sweep (a half or the middle when they name one); fixed options are spread
    /// evenly from up / left to down / right in the order the device lists them.
    public static func position(of value: String?, among options: [String], axis: Axis) -> Position {
        guard let value, !isOff(value) else { return .fixed(0) }
        let t = Set(tokens(value))
        let first = !t.isDisjoint(with: firstWords)
        let last = !t.isDisjoint(with: lastWords)

        if isSweep(value, axis: axis) {
            if first && last { return .sweep(.full) }
            if first { return .sweep(.first) }
            if last { return .sweep(.last) }
            if !t.isDisjoint(with: middleWords) { return .sweep(.middle) }
            return .sweep(.full)
        }
        // Any other axis's swing ("horizontal" on the vertical louver) leaves this one centred.
        if isSweep(value) { return .fixed(0) }

        let fixed = options.filter { !isSweep($0) && !isOff($0) }
        if let i = fixed.firstIndex(of: value), fixed.count > 1 {
            return .fixed(-1 + 2 * Double(i) / Double(fixed.count - 1))
        }
        if first && !last { return .fixed(-1) }
        if last && !first { return .fixed(1) }
        return .fixed(0)
    }

    /// Short label for a tile: "Swing", "Up swing", "Middle", "Off".
    public static func shortName(_ value: String?) -> String {
        guard let value, value != "unknown", value != "unavailable" else { return "–" }
        let t = tokens(value)
        let core = t.filter { !["flow", "fix", "fixed", "swing", "position"].contains($0) }
        if isSweep(value) {
            if core.isEmpty || (Set(core) == ["up", "down"]) || (Set(core) == ["left", "right"])
                || ["on", "both", "auto", "vertical", "horizontal"].contains(value.lowercased())
            {
                return "Swing"
            }
            return (core.joined(separator: " ") + " swing").capitalizedFirst
        }
        if core.isEmpty { return value.capitalizedFirst }
        return core.joined(separator: " ").capitalizedFirst
    }
}

/// A rough fan strength from a fan mode name, for the airflow animation.
public enum FanLevel: Int, Sendable, Comparable {
    case quiet, low, medium, high, turbo, auto

    public static func < (a: FanLevel, b: FanLevel) -> Bool { a.rawValue < b.rawValue }

    public init(_ name: String?) {
        let n = (name ?? "").lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if has("turbo", "strong", "max", "boost", "powerful", "super") {
            self = .turbo
        } else if has("quiet", "silent", "sleep", "mute", "night") {
            self = .quiet
        } else if has("medium", "mid", "middle", "moderate") {
            self = .medium
        } else if has("high") {
            self = .high
        } else if has("low") {
            self = .low
        } else if let level = Int(n.filter(\.isNumber)), !n.isEmpty {
            self = [.low, .low, .medium, .high, .turbo][min(4, max(0, level))]
        } else {
            self = .auto
        }
    }
}

extension String {
    /// "up swing" → "Up swing".
    public var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
