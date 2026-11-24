import Testing

@testable import HAKit

@Suite struct LayoutGeneratorTests {
    /// A bedroom with a WLED strip, a LocalTuya-style A/C, a 3-gang switch hub, sensors and a scene.
    static let catalog: EntityCatalog = {
        func e(_ id: String, _ name: String, device: String? = nil, area: String? = "bedroom",
               category: CatalogEntity.Category? = nil) -> CatalogEntity {
            CatalogEntity(entityID: id, name: name, areaID: area, deviceID: device, category: category)
        }
        func s(_ id: String, _ state: String = "on", _ deviceClass: String? = nil) -> HAState {
            HAState(entityID: id, state: state, attributes: deviceClass.map { ["device_class": .string($0)] } ?? [:])
        }
        let entities = [
            e("light.strip", "Strip", device: "wled"),
            e("select.strip_preset", "Strip Preset", device: "wled"),
            e("number.strip_speed", "Strip Speed", device: "wled", category: .config),
            e("sensor.strip_signal", "Strip Signal", device: "wled", category: .diagnostic),
            e("climate.bed_ac", "Bed AC", device: "ac"),
            e("select.bed_ac_fan_speed", "Bed AC Fan Speed", device: "ac"),
            e("select.bed_ac_up_down_air_flow", "Bed AC Up-Down Air Flow", device: "ac"),
            e("select.bed_ac_left_right_air_flow", "Bed AC Left-Right Air Flow", device: "ac"),
            e("select.bed_ac_sleep_mode", "Bed AC Sleep Mode", device: "ac"),
            e("switch.bed_ac_eco", "Bed AC Eco", device: "ac"),
            e("switch.bed_ac_display", "Bed AC Display", device: "ac"),
            e("switch.hub_1", "Hub Switch 1", device: "hub"),
            e("switch.hub_2", "Hub Switch 2", device: "hub"),
            e("select.hub_power_on_behaviour", "Hub Power-on behaviour", device: "hub", category: .config),
            e("sensor.bed_temperature", "Bed Temperature"),
            e("sensor.bed_humidity", "Bed Humidity"),
            e("sensor.bed_battery", "Bed Sensor Battery"),
            e("binary_sensor.bed_window", "Bed Window"),
            e("scene.bed_night", "Night"),
            e("camera.bed", "Bed Camera"),
            e("light.hall", "Hall", area: nil),
        ]
        let states = [
            s("light.strip"), s("select.strip_preset"), s("number.strip_speed"), s("sensor.strip_signal"),
            s("climate.bed_ac", "cool"), s("select.bed_ac_fan_speed"), s("select.bed_ac_up_down_air_flow"),
            s("select.bed_ac_left_right_air_flow"), s("select.bed_ac_sleep_mode"), s("switch.bed_ac_eco"),
            s("switch.bed_ac_display"), s("switch.hub_1"), s("switch.hub_2"), s("select.hub_power_on_behaviour"),
            s("sensor.bed_temperature", "24", "temperature"), s("sensor.bed_humidity", "60", "humidity"),
            s("sensor.bed_battery", "90", "battery"), s("binary_sensor.bed_window", "off", "window"),
            s("scene.bed_night", "x"), s("camera.bed", "idle"), s("light.hall"),
        ]
        return EntityCatalog(
            areas: [HAArea(id: "bedroom", name: "Master Bedroom", icon: "mdi:bed")],
            devices: [
                HADevice(id: "wled", name: "Strip"), HADevice(id: "ac", name: "Bed AC"), HADevice(id: "hub", name: "Hub"),
            ],
            entities: entities, states: states)
    }()

    @Test func roomBasics() {
        let room = LayoutGenerator.room(for: "bedroom", in: Self.catalog)
        #expect(room.name == "Master Bedroom")
        #expect(room.icon == "bed.double")
        #expect(room.areaID == "bedroom")
        #expect(room.headerSensors == ["sensor.bed_temperature", "sensor.bed_humidity"])
        #expect(room.sections.map(\.title) == ["Lights", "Climate", "Switches", "Sensors", "Scenes"])
        #expect(room.sections[1].style == .rows)
        #expect(room.sections.last?.style == .pills)
    }

    @Test func wledGetsPresetAndSpeed() throws {
        let room = LayoutGenerator.room(for: "bedroom", in: Self.catalog)
        let strip = try #require(room.sections[0].cards.first)
        #expect(strip.entityID == "light.strip")
        #expect(strip.attachment(.preset)?.entityID == "select.strip_preset")
        #expect(strip.attachment(.speed)?.entityID == "number.strip_speed")
        #expect(strip.attachments.count == 2)  // diagnostic signal sensor is left out
    }

    @Test func acGetsSelectsAndFeatures() throws {
        let room = LayoutGenerator.room(for: "bedroom", in: Self.catalog)
        let ac = try #require(room.sections[1].cards.first)
        #expect(ac.attachment(.fanSpeed)?.entityID == "select.bed_ac_fan_speed")
        #expect(ac.attachment(.swingVertical)?.entityID == "select.bed_ac_up_down_air_flow")
        #expect(ac.attachment(.swingHorizontal)?.entityID == "select.bed_ac_left_right_air_flow")
        #expect(ac.attachment(.sleep)?.entityID == "select.bed_ac_sleep_mode")
        let features = ac.attachments(.feature)
        #expect(features.map(\.name) == ["Display", "Eco"])
        #expect(features.map(\.icon) == ["light.max", "leaf"])
    }

    @Test func switchesKeepTheirOwnCardsAndShareThePowerOnSetting() throws {
        let room = LayoutGenerator.room(for: "bedroom", in: Self.catalog)
        let switches = room.sections[2].cards
        // The A/C's feature switches became attachments, not cards.
        #expect(switches.map(\.entityID) == ["switch.hub_1", "switch.hub_2"])
        #expect(switches.allSatisfy { $0.attachment(.powerOnBehaviour)?.entityID == "select.hub_power_on_behaviour" })
    }

    @Test func sensorsAreFiltered() {
        let room = LayoutGenerator.room(for: "bedroom", in: Self.catalog)
        let sensors = room.sections[3].cards.map(\.entityID)
        #expect(sensors == ["sensor.bed_humidity", "sensor.bed_temperature", "binary_sensor.bed_window"])
        #expect(!room.sections.flatMap(\.cards).contains { $0.entityID == "camera.bed" })
    }

    @Test func otherRoomHasUnassignedEntities() {
        let room = LayoutGenerator.room(for: nil, in: Self.catalog)
        #expect(room.name == "Other")
        #expect(room.sections.flatMap(\.cards).map(\.entityID) == ["light.hall"])
    }

    @Test func singleCardGetsAttachments() {
        let card = LayoutGenerator.card(for: "light.strip", in: Self.catalog)
        #expect(card.kind == .light)
        #expect(card.attachments.count == 2)
    }

    @Test func roomIcons() {
        #expect(LayoutGenerator.icon(for: HAArea(id: "k", name: "Kitchen")) == "fork.knife")
        #expect(LayoutGenerator.icon(for: HAArea(id: "x", name: "Den", icon: "mdi:sofa")) == "sofa")
        #expect(LayoutGenerator.icon(for: HAArea(id: "y", name: "Attic")) == "house")
        #expect(LayoutGenerator.icon(for: nil) == "house")
    }
}
