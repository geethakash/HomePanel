import Foundation
import Testing

@testable import HAKit

@Suite struct PanelConfigTests {
    @Test func roundTrip() throws {
        let config = SampleConfig.make()
        let decoded = try PanelConfig.decode(try config.encoded())
        #expect(decoded == config)
    }

    @Test func missingFieldsGetDefaults() throws {
        let json = #"{"rooms":[{"name":"Den","sections":[{"title":"Lights","cards":[{"entityID":"light.desk"}]}]}]}"#
        let config = try PanelConfig.decode(Data(json.utf8))
        #expect(config.version == 1)
        let card = try #require(config.rooms.first?.sections.first?.cards.first)
        #expect(card.kind == .light)
        #expect(card.hidden == false)
        #expect(card.attachments.isEmpty)
        #expect(config.rooms.first?.icon == "house")
        #expect(config.rooms.first?.sections.first?.style == .grid)
    }

    @Test func kindFromDomain() {
        #expect(Card.Kind.forEntity("switch.x") == .toggle)
        #expect(Card.Kind.forEntity("input_boolean.x") == .toggle)
        #expect(Card.Kind.forEntity("media_player.tv") == .media)
        #expect(Card.Kind.forEntity("alarm_control_panel.home") == .alarm)
        #expect(Card.Kind.forEntity("binary_sensor.door") == .binarySensor)
    }

    @Test func sampleLayout() throws {
        let config = SampleConfig.make()
        let room = try #require(config.rooms.first)
        #expect(config.lastRoomID == room.id)
        #expect(config.room(room.id)?.name == "Study")
        let light = room.sections[1].cards[0]
        #expect(light.attachment(.preset)?.entityID == "select.desk_strip_preset")
        #expect(config.locate(card: light.id)?.section.title == "Lights")
        #expect(PanelConfig.entityIDs(in: room).first == "sensor.study_temperature")
    }

    @Test func entityIDsAreUnique() {
        let ids = SampleConfig.make().allEntityIDs
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 14)
    }
}

/// A made-up room with each kind of attachment.
enum SampleConfig {
    static func make() -> PanelConfig {
        let switches = CardSection(
            title: "Switches", style: .grid,
            cards: (1...2).map { n in
                Card(
                    entityID: "switch.study_\(n)", kind: .toggle, name: "Switch \(n)",
                    attachments: [
                        Attachment("timer.study_\(n)_off", role: .offTimer),
                        Attachment("select.study_power_on", role: .powerOnBehaviour),
                    ])
            })
        let lights = CardSection(
            title: "Lights", style: .grid,
            cards: [
                Card(
                    entityID: "light.desk_strip", kind: .light,
                    attachments: [
                        Attachment("select.desk_strip_preset", role: .preset),
                        Attachment("number.desk_strip_speed", role: .speed),
                    ])
            ])
        let climate = CardSection(
            title: "Climate", style: .rows,
            cards: [
                Card(
                    entityID: "climate.study", kind: .climate,
                    attachments: [
                        Attachment("select.study_ac_fan", role: .fanSpeed),
                        Attachment("select.study_ac_vane", role: .swingVertical),
                        Attachment("switch.study_ac_eco", role: .feature, name: "Eco", icon: "leaf"),
                    ])
            ])
        let room = Room(
            name: "Study", icon: "books.vertical",
            headerSensors: ["sensor.study_temperature", "sensor.study_humidity"],
            sections: [switches, lights, climate])
        return PanelConfig(rooms: [room], lastRoomID: room.id)
    }
}

@Suite @MainActor struct ConfigStoreTests {
    private func tempURL() -> URL {
        URL.temporaryDirectory.appending(path: "homepanel-tests-\(UUID().uuidString)/config.json")
    }

    @Test func createsSavesAndReloads() throws {
        let url = tempURL()
        let store = ConfigStore(fileURL: url, makeInitial: SampleConfig.make)
        #expect(store.fileExists)
        store.update { $0.rooms[0].name = "Bedroom" }

        let reloaded = ConfigStore(fileURL: url, makeInitial: { PanelConfig() })
        #expect(reloaded.config.rooms.first?.name == "Bedroom")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func unreadableFileIsKeptAside() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let store = ConfigStore(fileURL: url, makeInitial: { PanelConfig() })
        #expect(store.config.rooms.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(files.contains { $0.hasPrefix("config.unreadable-") })
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func importReplacesConfig() throws {
        let url = tempURL()
        let store = ConfigStore(fileURL: url, makeInitial: { PanelConfig() })
        let data = try SampleConfig.make().encoded()
        try store.importConfig(from: data)
        #expect(store.config.rooms.count == 1)
        #expect(throws: (any Error).self) { try store.importConfig(from: Data("nope".utf8)) }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
