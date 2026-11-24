import Testing

@testable import HAKit

@Suite struct AirflowTests {
    // A LocalTuya A/C's up-down and left-right selects.
    let upDown = [
        "Up-Down Flow", "Up Flow", "Down Flow", "Up Fix", "Above Up Fix", "Middle Fix", "Above Down Fix", "Down Fix",
    ]
    let leftRight = [
        "Left-Right Flow", "Left Flow", "Middle Flow", "Right Flow", "Left Fix", "A Bit Left Fix", "Middle Fix",
        "A Bit Right Fix", "Right Fix",
    ]

    @Test func selectOptionsSweep() {
        #expect(Airflow.position(of: "Up-Down Flow", among: upDown, axis: .vertical) == .sweep(.full))
        #expect(Airflow.position(of: "Up Flow", among: upDown, axis: .vertical) == .sweep(.first))
        #expect(Airflow.position(of: "Down Flow", among: upDown, axis: .vertical) == .sweep(.last))
        #expect(Airflow.position(of: "Middle Flow", among: leftRight, axis: .horizontal) == .sweep(.middle))
        #expect(Airflow.position(of: "Left-Right Flow", among: leftRight, axis: .horizontal) == .sweep(.full))
    }

    @Test func fixedOptionsSpreadInListOrder() {
        #expect(Airflow.position(of: "Up Fix", among: upDown, axis: .vertical) == .fixed(-1))
        #expect(Airflow.position(of: "Above Up Fix", among: upDown, axis: .vertical) == .fixed(-0.5))
        #expect(Airflow.position(of: "Middle Fix", among: upDown, axis: .vertical) == .fixed(0))
        #expect(Airflow.position(of: "Down Fix", among: upDown, axis: .vertical) == .fixed(1))
        #expect(Airflow.position(of: "A Bit Right Fix", among: leftRight, axis: .horizontal) == .fixed(0.5))
    }

    @Test func climateSwingModes() {
        let modes = ["off", "vertical", "horizontal", "both"]
        #expect(Airflow.position(of: "vertical", among: modes, axis: .vertical) == .sweep(.full))
        #expect(Airflow.position(of: "horizontal", among: modes, axis: .vertical) == .fixed(0))
        #expect(Airflow.position(of: "horizontal", among: modes, axis: .horizontal) == .sweep(.full))
        #expect(Airflow.position(of: "both", among: modes, axis: .horizontal) == .sweep(.full))
        #expect(Airflow.position(of: "off", among: modes, axis: .vertical) == .fixed(0))
        #expect(Airflow.position(of: "on", among: ["on", "off"], axis: .vertical) == .sweep(.full))
    }

    @Test func numberedPositions() {
        let vanes = ["auto", "1", "2", "3", "4", "5", "swing"]
        #expect(Airflow.position(of: "auto", among: vanes, axis: .vertical) == .sweep(.full))
        #expect(Airflow.position(of: "1", among: vanes, axis: .vertical) == .fixed(-1))
        #expect(Airflow.position(of: "3", among: vanes, axis: .vertical) == .fixed(0))
        #expect(Airflow.position(of: "5", among: vanes, axis: .vertical) == .fixed(1))
    }

    @Test func shortNames() {
        #expect(Airflow.shortName("Up-Down Flow") == "Swing")
        #expect(Airflow.shortName("Up Flow") == "Up swing")
        #expect(Airflow.shortName("Middle Fix") == "Middle")
        #expect(Airflow.shortName("A Bit Left Fix") == "A bit left")
        #expect(Airflow.shortName("vertical") == "Swing")
        #expect(Airflow.shortName("off") == "Off")
        #expect(Airflow.shortName(nil) == "–")
    }

    @Test func fanLevels() {
        #expect(FanLevel("Quiet") == .quiet)
        #expect(FanLevel("Low") == .low)
        #expect(FanLevel("Medium") == .medium)
        #expect(FanLevel("middle") == .medium)
        #expect(FanLevel("High") == .high)
        #expect(FanLevel("Turbo") == .turbo)
        #expect(FanLevel("Auto") == .auto)
        #expect(FanLevel("level 3") == .high)
        #expect(FanLevel(nil) == .auto)
    }

    @Test func hvacModeOrder() {
        #expect(HVACMode.sorted(["off", "heat", "cool", "heat_cool", "eco"]) == ["cool", "heat", "heat_cool", "eco"])
        #expect(HVACMode.actionName("cooling") == "Cooling")
        #expect(HVACMode.actionName("off") == nil)
    }
}

@Suite struct CapabilityTests {
    @Test func lightColorModes() {
        let onoff = HAState(entityID: "light.a", state: "on", attributes: ["supported_color_modes": ["onoff"]])
        #expect(!onoff.supportsBrightness && !onoff.supportsColor && !onoff.supportsColorTemp)
        let ct = HAState(entityID: "light.b", state: "on", attributes: ["supported_color_modes": ["color_temp", "xy"]])
        #expect(ct.supportsBrightness && ct.supportsColor && ct.supportsColorTemp)
        let dim = HAState(entityID: "light.c", state: "off", attributes: ["supported_color_modes": ["brightness"]])
        #expect(dim.supportsBrightness && !dim.supportsColor)
        let legacy = HAState(entityID: "light.d", state: "off")
        #expect(legacy.supportsBrightness && !legacy.supportsColor)
    }
}
