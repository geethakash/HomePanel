import Foundation
import Testing

@testable import HAKit

@Suite struct DeviceTextTests {
    private func s(_ id: String, _ state: String, _ attrs: [String: JSONValue] = [:]) -> HAState {
        HAState(entityID: id, state: state, attributes: attrs)
    }

    @Test func covers() {
        #expect(DeviceText.summary(s("cover.blind", "open", ["current_position": 40])) == "Open · 40%")
        #expect(DeviceText.summary(s("cover.blind", "open", ["current_position": 100])) == "Open")
        #expect(DeviceText.summary(s("cover.garage", "closing")) == "Closing…")
        #expect(DeviceText.isActive(s("cover.blind", "open")))
        #expect(!DeviceText.isActive(s("cover.blind", "closed")))
        let f = s("cover.blind", "open", ["supported_features": 15]).coverFeatures
        #expect(f.contains([.open, .close, .stop, .setPosition]) && !f.contains(.setTiltPosition))
    }

    @Test func fans() {
        #expect(DeviceText.summary(s("fan.desk", "on", ["percentage": 66])) == "On · 66%")
        #expect(DeviceText.summary(s("fan.desk", "on", ["preset_mode": "nature"])) == "On · Nature")
        #expect(DeviceText.summary(s("fan.desk", "off")) == "Off")
        let f = s("fan.desk", "on", ["supported_features": 9]).fanFeatures
        #expect(f.contains(.setSpeed) && f.contains(.presetMode) && !f.contains(.oscillate))
    }

    @Test func media() {
        #expect(DeviceText.summary(s("media_player.tv", "playing", ["media_title": "Song"])) == "Playing · Song")
        #expect(DeviceText.summary(s("media_player.tv", "paused", ["app_name": "Netflix"])) == "Paused · Netflix")
        #expect(DeviceText.summary(s("media_player.tv", "standby")) == "Idle")
        #expect(DeviceText.isActive(s("media_player.tv", "playing")))
        #expect(!DeviceText.isActive(s("media_player.tv", "off")))
    }

    @Test func mediaPositionAdvancesWhilePlaying() {
        let updated = "2026-11-24T08:00:00+00:00"
        let attrs: [String: JSONValue] = [
            "media_position": 30, "media_duration": 200, "media_position_updated_at": .string(updated),
        ]
        let start = HADate.parse(updated)!
        #expect(s("media_player.a", "playing", attrs).mediaPosition(at: start.addingTimeInterval(10)) == 40)
        #expect(s("media_player.a", "paused", attrs).mediaPosition(at: start.addingTimeInterval(10)) == 30)
        #expect(s("media_player.a", "playing", attrs).mediaPosition(at: start.addingTimeInterval(500)) == 200)
    }

    @Test func locksAndAlarms() {
        #expect(DeviceText.summary(s("lock.front", "unlocked")) == "Unlocked")
        #expect(DeviceText.isActive(s("lock.front", "unlocked")))
        #expect(!DeviceText.isActive(s("lock.front", "locked")))
        #expect(DeviceText.summary(s("alarm_control_panel.home", "armed_away")) == "Armed away")
        #expect(DeviceText.isActive(s("alarm_control_panel.home", "armed_home")))
        let alarm = s("alarm_control_panel.home", "disarmed", ["supported_features": 3, "code_format": "number"])
        #expect(alarm.alarmFeatures == [.armHome, .armAway])
        #expect(alarm.codeFormat == "number" && alarm.codeArmRequired)
    }

    @Test func sensors() {
        #expect(DeviceText.summary(s("binary_sensor.door", "on", ["device_class": "door"])) == "Open")
        #expect(DeviceText.summary(s("binary_sensor.hall", "off", ["device_class": "motion"])) == "Clear")
        #expect(DeviceText.summary(s("binary_sensor.x", "on")) == "On")
        #expect(DeviceText.summary(s("sensor.t", "21.53", ["unit_of_measurement": "°C"])) == "21.5°C")
        #expect(DeviceText.summary(s("sensor.h", "48", ["unit_of_measurement": "%"])) == "48%")
        #expect(DeviceText.summary(s("sensor.p", "1234.7", ["unit_of_measurement": "W"])) == "\(1235.formatted()) W")
        #expect(DeviceText.summary(s("sensor.mode", "on_battery")) == "On battery")
        #expect(DeviceText.summary(s("sensor.x", "unavailable")) == "Unavailable")
    }
}
