import Foundation
import Testing

@testable import HAKit

@Suite struct CompressedStatesTests {
    private func json(_ s: String) throws -> JSONValue { try JSONValue.parse(Data(s.utf8)) }

    @Test func fullSnapshot() throws {
        var states: [String: HAState] = [:]
        let event = try json(
            """
            {"a":{"switch.hall_1":{"s":"on","a":{"friendly_name":"Switch 1"},"c":"01H","lc":1700000000.5},
                  "light.shelf_strip":{"s":"off","a":{"effect_list":["Solid","Rainbow"]},"lc":1700000000,"lu":1700000100}}}
            """)
        CompressedStates.apply(event, to: &states)
        #expect(states.count == 2)
        let sw = try #require(states["switch.hall_1"])
        #expect(sw.isOn)
        #expect(sw.friendlyName == "Switch 1")
        #expect(sw.lastChanged == Date(timeIntervalSince1970: 1_700_000_000.5))
        #expect(sw.lastUpdated == sw.lastChanged)
        let strip = try #require(states["light.shelf_strip"])
        #expect(strip.effectList == ["Solid", "Rainbow"])
        #expect(strip.lastUpdated == Date(timeIntervalSince1970: 1_700_000_100))
    }

    @Test func changesAndRemovals() throws {
        var states: [String: HAState] = [:]
        CompressedStates.apply(
            try json(#"{"a":{"light.x":{"s":"on","a":{"brightness":255,"rgb_color":[255,0,0],"effect":"Solid"},"lc":1}}}"#),
            to: &states)

        let touched = CompressedStates.apply(
            try json(#"{"c":{"light.x":{"+":{"s":"off","a":{"brightness":128},"lc":5},"-":{"a":["effect"]}}}}"#),
            to: &states)
        #expect(touched == ["light.x"])
        let light = try #require(states["light.x"])
        #expect(light.state == "off")
        #expect(light.brightnessPct == 50)
        #expect(light.rgb == [255, 0, 0])
        #expect(light.effect == nil)
        #expect(light.lastChanged == Date(timeIntervalSince1970: 5))

        // Attribute-only change: lu moves, lc stays, state string not touched.
        let touched2 = CompressedStates.apply(
            try json(#"{"c":{"light.x":{"+":{"a":{"brightness":255},"lu":9}}}}"#), to: &states)
        #expect(touched2.isEmpty)
        #expect(states["light.x"]?.lastChanged == Date(timeIntervalSince1970: 5))
        #expect(states["light.x"]?.lastUpdated == Date(timeIntervalSince1970: 9))

        CompressedStates.apply(try json(#"{"r":["light.x"]}"#), to: &states)
        #expect(states.isEmpty)
    }

    @Test func changeForUnknownEntityIsIgnored() throws {
        var states: [String: HAState] = [:]
        CompressedStates.apply(try json(#"{"c":{"switch.nope":{"+":{"s":"on"}}}}"#), to: &states)
        #expect(states.isEmpty)
    }
}

@Suite struct JSONValueTests {
    @Test func integersSerialiseWithoutDecimals() throws {
        let v: JSONValue = ["id": .integer(7), "temp": 25.5, "on": true]
        let s = String(decoding: try v.serialized(), as: UTF8.self)
        #expect(s.contains("\"id\":7"))
        #expect(s.contains("25.5"))
        #expect(s.contains("true"))
    }

    @Test func booleansStayBooleans() throws {
        let v = try JSONValue.parse(Data(#"{"a":true,"b":1}"#.utf8))
        #expect(v["a"] == .bool(true))
        #expect(v["b"] == .number(1))
    }
}

@Suite struct HelpersTests {
    @Test func dates() {
        #expect(HADate.parse("2026-11-24T10:00:00+00:00") == Date(timeIntervalSince1970: 1_795_514_400))
        #expect(HADate.parse("2026-11-24T10:00:00.123456+00:00") != nil)
    }

    @Test func durations() {
        #expect(HADate.parseDuration("0:15:00") == 900)
        #expect(HADate.parseDuration("2:00:00") == 7200)
        #expect(HADate.formatDuration(3600) == "01:00:00")
    }

    @Test func webSocketURL() {
        let c = HAClient.Configuration(baseURL: URL(string: "http://192.168.1.20:8123/")!, token: "x")
        #expect(c.webSocketURL?.absoluteString == "ws://192.168.1.20:8123/api/websocket")
        let s = HAClient.Configuration(baseURL: URL(string: "https://ha.example.com")!, token: "x")
        #expect(s.webSocketURL?.absoluteString == "wss://ha.example.com/api/websocket")
    }

    @Test func urlValidation() {
        #expect(SharedConfig.validatedURL("http://192.168.1.20:8123") != nil)
        #expect(SharedConfig.validatedURL("192.168.1.20") == nil)
        #expect(SharedConfig.validatedURL("ftp://x") == nil)
    }
}
