import AppKit
import HAKit
import SwiftUI

/// Icons and colors that follow a device's state (an open garage door, an unlocked lock…).
/// A card's own icon, if set, always wins.
enum DeviceIcon {
    static func symbol(_ card: Card, _ state: HAState?) -> String {
        if let icon = card.icon { return icon }
        guard let state else { return card.kind.defaultIcon }
        let on = DeviceText.isActive(state)
        let name: String? =
            switch card.kind {
            case .cover: cover(state.deviceClass, open: on)
            case .fan: "fan"
            case .media: media(state.deviceClass)
            case .lock: on ? "lock.open" : "lock"
            case .alarm:
                state.state == "triggered" ? "exclamationmark.shield" : (on ? "checkmark.shield" : "shield")
            case .binarySensor: binarySensor(state.deviceClass, on: state.isOn)
            case .sensor: HeaderReadout.icon(state)
            default: nil
            }
        return name.map(SFSymbol.or) ?? card.kind.defaultIcon
    }

    /// Icon circle color when the tile is active, and whether it's light (for a dark symbol).
    static func onColor(_ card: Card, _ state: HAState?) -> (color: Color, isLight: Bool) {
        switch card.kind {
        case .cover: (Color(hex: 0x64D2FF), true)
        case .fan: (Color(hex: 0x64D2FF), true)
        case .media: (Color(hex: 0xBF5AF2), false)
        case .lock: (Theme.amber, true)
        case .alarm: state?.state == "triggered" ? (Color(hex: 0xFF453A), false) : (Color(hex: 0x30D158), true)
        case .binarySensor: (Theme.amber, true)
        default: (Theme.bulbYellow, true)
        }
    }

    private static func cover(_ deviceClass: String?, open: Bool) -> String {
        switch deviceClass {
        case "garage": open ? "door.garage.open" : "door.garage.closed"
        case "door", "gate": open ? "door.left.hand.open" : "door.left.hand.closed"
        case "window": open ? "window.vertical.open" : "window.vertical.closed"
        case "curtain": open ? "curtains.open" : "curtains.closed"
        case "awning": "awning"
        default: open ? "blinds.vertical.open" : "blinds.vertical.closed"
        }
    }

    private static func media(_ deviceClass: String?) -> String {
        switch deviceClass {
        case "tv": "tv"
        case "speaker": "hifispeaker"
        case "receiver": "hifireceiver"
        default: "play.rectangle"
        }
    }

    private static func binarySensor(_ deviceClass: String?, on: Bool) -> String {
        switch deviceClass {
        case "door", "garage_door", "opening": on ? "door.left.hand.open" : "door.left.hand.closed"
        case "window": on ? "window.vertical.open" : "window.vertical.closed"
        case "motion", "moving": on ? "figure.walk.motion" : "figure.stand"
        case "occupancy", "presence": on ? "person.fill" : "person"
        case "moisture": on ? "drop.triangle" : "drop"
        case "smoke": "smoke"
        case "gas", "carbon_monoxide": "aqi.medium"
        case "heat": "thermometer.sun"
        case "cold": "thermometer.snowflake"
        case "connectivity": on ? "wifi" : "wifi.slash"
        case "battery": on ? "battery.25" : "battery.100"
        case "battery_charging": "battery.100.bolt"
        case "plug", "power": "powerplug"
        case "light": on ? "sun.max" : "moon"
        case "lock": on ? "lock.open" : "lock"
        case "sound": "waveform"
        case "vibration": "waveform.path"
        case "problem", "safety", "tamper": on ? "exclamationmark.triangle" : "checkmark.circle"
        case "update": "arrow.down.circle"
        case "running": on ? "play.circle" : "stop.circle"
        default: on ? "circle.inset.filled" : "circle"
        }
    }
}

extension SFSymbol {
    /// The symbol if this macOS has it, otherwise a generic one.
    static func or(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "circle.dashed"
    }
}
