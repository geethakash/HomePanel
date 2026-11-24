import Foundation
import Testing

@testable import HAKit

/// Registry replies shaped like Home Assistant's, for a made-up two-room house.
private enum Fixture {
    static func json(_ s: String) -> JSONValue { try! JSONValue.parse(Data(s.utf8)) }

    static let areas = json(
        #"""
        [{"area_id":"living_room","name":"Living Room","icon":"mdi:sofa","floor_id":null,"aliases":[],"labels":[]},
         {"area_id":"bedroom","name":"Bedroom","icon":null,"floor_id":"upstairs","aliases":[],"labels":[]}]
        """#)

    static let devices = json(
        #"""
        [{"id":"dev_wled","name":"WLED","name_by_user":"Shelf Strip","area_id":"living_room","manufacturer":"WLED","model":"ESP32","disabled_by":null},
         {"id":"dev_ac","name":"AC","name_by_user":null,"area_id":"bedroom","manufacturer":"Tuya","model":null,"disabled_by":null},
         {"id":"dev_old","name":"Old Plug","area_id":"bedroom","disabled_by":"user"}]
        """#)

    static let entitiesForDisplay = json(
        #"""
        {"entity_categories":{"0":"config","1":"diagnostic"},
         "entities":[
          {"ei":"light.shelf","di":"dev_wled","pl":"wled","en":"Shelf"},
          {"ei":"select.shelf_preset","di":"dev_wled","pl":"wled","en":"Preset"},
          {"ei":"number.shelf_speed","di":"dev_wled","pl":"wled","en":"Speed","ec":0},
          {"ei":"sensor.shelf_signal","di":"dev_wled","pl":"wled","ec":1},
          {"ei":"climate.bedroom_ac","di":"dev_ac","pl":"localtuya"},
          {"ei":"switch.ac_eco","di":"dev_ac","pl":"localtuya","ai":"living_room"},
          {"ei":"switch.hidden_thing","pl":"template","hb":true,"ai":"bedroom"},
          {"ei":"sensor.gone","pl":"template","ai":"bedroom"}
         ]}
        """#)

    static let states = json(
        #"""
        [{"entity_id":"light.shelf","state":"on","attributes":{"friendly_name":"Shelf Strip Shelf"},"last_changed":"2026-11-24T08:00:00.123456+00:00","last_updated":"2026-11-24T08:00:00.123456+00:00"},
         {"entity_id":"select.shelf_preset","state":"Rainbow","attributes":{"friendly_name":"Shelf Strip Preset","options":["Rainbow","Fire"]},"last_changed":"2026-11-24T08:00:00+00:00","last_updated":"2026-11-24T08:00:00+00:00"},
         {"entity_id":"number.shelf_speed","state":"128","attributes":{"friendly_name":"Shelf Strip Speed"},"last_changed":"2026-11-24T08:00:00+00:00","last_updated":"2026-11-24T08:00:00+00:00"},
         {"entity_id":"sensor.shelf_signal","state":"-60","attributes":{},"last_changed":"2026-11-24T08:00:00+00:00","last_updated":"2026-11-24T08:00:00+00:00"},
         {"entity_id":"climate.bedroom_ac","state":"cool","attributes":{"friendly_name":"Bedroom A/C"},"last_changed":"2026-11-24T08:00:00+00:00","last_updated":"2026-11-24T08:00:00+00:00"},
         {"entity_id":"switch.ac_eco","state":"off","attributes":{"friendly_name":"A/C Eco"},"last_changed":"2026-11-24T08:00:00+00:00","last_updated":"2026-11-24T08:00:00+00:00"},
         {"entity_id":"switch.hidden_thing","state":"off","attributes":{},"last_changed":"2026-11-24T08:00:00+00:00","last_updated":"2026-11-24T08:00:00+00:00"},
         {"entity_id":"input_boolean.guest_mode","state":"off","attributes":{"friendly_name":"Guest Mode","icon":"mdi:account"},"last_changed":"2026-11-24T08:00:00+00:00","last_updated":"2026-11-24T08:00:00+00:00"}]
        """#)

    static let config = json(
        #"{"unit_system":{"temperature":"°F","length":"mi"},"version":"2026.11.2","location_name":"Home"}"#)

    static var catalog: EntityCatalog {
        EntityCatalog(areas: areas, devices: devices, entities: entitiesForDisplay, states: states, config: config)
    }
}

@Suite struct EntityCatalogTests {
    @Test func decodesAreasAndDevices() {
        let c = Fixture.catalog
        #expect(c.areas.map(\.name) == ["Bedroom", "Living Room"])  // sorted by name
        #expect(c.area("living_room")?.icon == "mdi:sofa")
        #expect(c.area("bedroom")?.floorID == "upstairs")
        #expect(c.devices["dev_wled"]?.name == "Shelf Strip")  // name_by_user wins
        #expect(c.devices["dev_ac"]?.name == "AC")
        #expect(c.devices["dev_old"] == nil)  // disabled devices are dropped
    }

    @Test func decodesCoreConfig() {
        let c = Fixture.catalog
        #expect(c.temperatureUnit == "°F")
        #expect(c.haVersion == "2026.11.2")
        #expect(c.locationName == "Home")
    }

    @Test func resolvesAreaFromDeviceUnlessEntityOverrides() {
        let c = Fixture.catalog
        #expect(c.entity("light.shelf")?.areaID == "living_room")  // from its device
        #expect(c.entity("climate.bedroom_ac")?.areaID == "bedroom")
        #expect(c.entity("switch.ac_eco")?.areaID == "living_room")  // entity's own area wins
    }

    @Test func namesComeFromStates() {
        let c = Fixture.catalog
        #expect(c.entity("light.shelf")?.name == "Shelf Strip Shelf")
        #expect(c.entity("sensor.shelf_signal")?.name == "sensor.shelf_signal")  // no friendly name
        #expect(c.entity("light.shelf")?.platform == "wled")
    }

    @Test func categoriesAndHidden() {
        let c = Fixture.catalog
        #expect(c.entity("number.shelf_speed")?.category == .config)
        #expect(c.entity("sensor.shelf_signal")?.category == .diagnostic)
        #expect(c.entity("switch.hidden_thing")?.hidden == true)
        #expect(c.entity("light.shelf")?.isPrimary == true)
        #expect(c.entity("number.shelf_speed")?.isPrimary == false)
    }

    @Test func skipsRegistryEntriesWithoutStateAndKeepsUnregisteredStates() {
        let c = Fixture.catalog
        #expect(c.entity("sensor.gone") == nil)
        let guest = c.entity("input_boolean.guest_mode")
        #expect(guest?.areaID == nil)
        #expect(guest?.name == "Guest Mode")
        #expect(guest?.icon == "mdi:account")
        #expect(c.states["light.shelf"]?.state == "on")
    }

    @Test func areaAndDeviceQueries() {
        let c = Fixture.catalog
        #expect(c.entities(inArea: "living_room").map(\.entityID) == ["switch.ac_eco", "select.shelf_preset", "light.shelf"])
        #expect(c.entities(inArea: "bedroom").map(\.entityID) == ["climate.bedroom_ac"])
        #expect(c.entities(ofDevice: "dev_wled").count == 4)
        #expect(c.primaryCountByArea["living_room"] == 3)
        #expect(c.primaryCountByArea[nil] == 1)
    }

    @Test func search() {
        let c = Fixture.catalog
        #expect(c.search("shelf").count == 4)
        #expect(c.search("shelf", primaryOnly: true).count == 2)
        #expect(c.search("", domains: ["climate"]).map(\.entityID) == ["climate.bedroom_ac"])
        #expect(c.search("eco", area: "bedroom").isEmpty)
    }

    @Test func readsAdminRegistryShape() {
        let full = Fixture.json(
            #"""
            [{"entity_id":"light.shelf","device_id":"dev_wled","area_id":null,"platform":"wled","entity_category":null,"hidden_by":null,"disabled_by":null,"name":null,"original_name":"Shelf"},
             {"entity_id":"number.shelf_speed","device_id":"dev_wled","entity_category":"config","hidden_by":null,"disabled_by":null},
             {"entity_id":"switch.hidden_thing","entity_category":null,"hidden_by":"user","disabled_by":null},
             {"entity_id":"switch.off","disabled_by":"integration"}]
            """#)
        let entries = EntityCatalog.registryEntries(full)
        #expect(entries.map(\.entityID) == ["light.shelf", "number.shelf_speed", "switch.hidden_thing"])
        #expect(entries[0].name == "Shelf")
        #expect(entries[1].category == .config)
        #expect(entries[2].hidden)
    }
}
