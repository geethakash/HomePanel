#if DEBUG
import Foundation
import HAKit

/// A made-up home for screenshots: a sample layout and live-looking states.
/// Debug builds only; nothing here talks to Home Assistant.
@MainActor
enum DemoHome {
    static func makeModel() -> AppModel {
        let file = URL.temporaryDirectory.appending(path: "homepanel-demo-\(UUID().uuidString)/config.json")
        let app = AppModel(config: ConfigStore(fileURL: file, makeInitial: layout), live: false)
        app.store.apply(["a": .object(states)])
        app.store.status = .connected
        return app
    }

    // MARK: Layout

    static func layout() -> PanelConfig {
        let living = Room(
            name: "Living Room", icon: "sofa",
            headerSensors: ["sensor.living_temperature", "sensor.living_humidity"],
            sections: [
                CardSection(title: "Lights", cards: [
                    Card(entityID: "light.ceiling", name: "Ceiling", icon: "light.recessed"),
                    Card(entityID: "light.floor_lamp", name: "Floor Lamp", icon: "lamp.floor"),
                    Card(entityID: "light.tv_strip", name: "TV Strip", icon: "light.strip.2", attachments: [
                        Attachment("select.tv_strip_preset", role: .preset),
                        Attachment("number.tv_strip_speed", role: .speed),
                    ]),
                ]),
                CardSection(title: "Climate", style: .rows, cards: [
                    Card(entityID: "climate.living_ac", name: "Living Room A/C", attachments: [
                        Attachment("switch.living_ac_eco", role: .feature, name: "Eco", icon: "leaf"),
                        Attachment("switch.living_ac_display", role: .feature, name: "Display", icon: "light.max"),
                        Attachment("switch.living_ac_quiet", role: .feature, name: "Quiet", icon: "moon"),
                    ]),
                ]),
                CardSection(title: "Devices", cards: [
                    Card(entityID: "fan.ceiling_fan", name: "Ceiling Fan"),
                    Card(entityID: "switch.coffee_machine", name: "Coffee", icon: "cup.and.saucer"),
                    Card(entityID: "media_player.living_tv", name: "TV"),
                    Card(entityID: "lock.front_door", name: "Front Door"),
                    Card(entityID: "binary_sensor.patio_door", name: "Patio Door"),
                    Card(entityID: "binary_sensor.hall_motion", name: "Hallway"),
                ]),
                CardSection(title: "Scenes", style: .pills, cards: [
                    Card(entityID: "scene.movie_night", name: "Movie Night", icon: "film"),
                    Card(entityID: "scene.good_morning", name: "Good Morning", icon: "sun.horizon"),
                    Card(entityID: "script.goodnight", name: "Goodnight", icon: "moon.stars"),
                ]),
            ])
        func simple(_ name: String, _ icon: String, _ ids: [String]) -> Room {
            Room(name: name, icon: icon, sections: [CardSection(title: "Devices", cards: ids.map { Card(entityID: $0) })])
        }
        let rooms = [
            living,
            simple("Kitchen", "fork.knife", ["light.k1", "light.k2", "switch.k3", "switch.k4", "sensor.k5"]),
            simple("Bedroom", "bed.double", ["light.b1", "light.b2", "climate.b3", "cover.b4"]),
            simple("Office", "desktopcomputer", ["light.o1", "switch.o2", "media_player.o3"]),
            simple("Garden", "leaf", ["light.g1", "switch.g2"]),
        ]
        return PanelConfig(rooms: rooms, lastRoomID: living.id)
    }

    // MARK: States (Home Assistant's compressed format: s = state, a = attributes, lc = last changed)

    static var states: [String: JSONValue] {
        let changed = Date.now.addingTimeInterval(-47 * 60).timeIntervalSince1970
        func entity(_ state: String, _ attributes: [String: JSONValue] = [:]) -> JSONValue {
            ["s": .string(state), "a": .object(attributes), "lc": .number(changed)]
        }
        return [
            "sensor.living_temperature": entity("22.5", ["unit_of_measurement": "°C", "device_class": "temperature"]),
            "sensor.living_humidity": entity("46", ["unit_of_measurement": "%", "device_class": "humidity"]),

            "light.ceiling": entity("on", [
                "friendly_name": "Ceiling", "brightness": 204, "color_mode": "color_temp",
                "color_temp_kelvin": 2900, "min_color_temp_kelvin": 2200, "max_color_temp_kelvin": 6500,
                "supported_color_modes": ["color_temp"],
            ]),
            "light.floor_lamp": entity("off", ["friendly_name": "Floor Lamp", "supported_color_modes": ["brightness"]]),
            "light.tv_strip": entity("on", [
                "friendly_name": "TV Strip", "brightness": 166, "color_mode": "rgb", "rgb_color": [124, 77, 255],
                "supported_color_modes": ["rgb"], "effect": "Aurora",
                "effect_list": ["Solid", "Aurora", "Breathe", "Candle", "Fireworks", "Rainbow", "Twinkle"],
            ]),
            "select.tv_strip_preset": entity("Movie", ["options": ["Chill", "Movie", "Party", "Sunset", "Focus"]]),
            "number.tv_strip_speed": entity("140", ["min": 0, "max": 255, "step": 1]),

            "climate.living_ac": entity("cool", [
                "friendly_name": "Living Room A/C", "temperature": 23, "current_temperature": 25.5,
                "hvac_modes": ["off", "cool", "dry", "fan_only", "heat", "auto"], "hvac_action": "cooling",
                "min_temp": 16, "max_temp": 30, "target_temp_step": 1,
                "fan_modes": ["auto", "low", "medium", "high"], "fan_mode": "medium",
                "swing_modes": ["off", "vertical", "horizontal", "both"], "swing_mode": "vertical",
                "preset_modes": ["none", "eco", "boost", "sleep"], "preset_mode": "none",
            ]),
            "switch.living_ac_eco": entity("on", ["friendly_name": "Eco"]),
            "switch.living_ac_display": entity("on", ["friendly_name": "Display"]),
            "switch.living_ac_quiet": entity("off", ["friendly_name": "Quiet"]),

            "fan.ceiling_fan": entity("on", ["friendly_name": "Ceiling Fan", "percentage": 66, "supported_features": 1]),
            "switch.coffee_machine": entity("off", ["friendly_name": "Coffee Machine"]),
            "media_player.living_tv": entity("playing", [
                "friendly_name": "Living Room TV", "device_class": "tv", "media_title": "Night Drive",
                "app_name": "Plex", "supported_features": 21437,
            ]),
            "lock.front_door": entity("locked", ["friendly_name": "Front Door"]),
            "binary_sensor.patio_door": entity("off", ["friendly_name": "Patio Door", "device_class": "door"]),
            "binary_sensor.hall_motion": entity("on", ["friendly_name": "Hallway", "device_class": "motion"]),

            "scene.movie_night": entity("2026-11-20T20:00:00+00:00", ["friendly_name": "Movie Night"]),
            "scene.good_morning": entity("2026-11-20T07:00:00+00:00", ["friendly_name": "Good Morning"]),
            "script.goodnight": entity("off", ["friendly_name": "Goodnight"]),
        ]
    }
}
#endif
