import HAKit
import SwiftUI

/// Alarm panels: the arm modes the panel supports, disarm, and a code pad when it needs a code.
struct AlarmScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card

    @State private var code = ""

    private static let modes: [(feature: AlarmFeatures, service: String, title: String, icon: String)] = [
        (.armHome, "alarm_arm_home", "Home", "house"),
        (.armAway, "alarm_arm_away", "Away", "figure.walk"),
        (.armNight, "alarm_arm_night", "Night", "moon"),
        (.armVacation, "alarm_arm_vacation", "Vacation", "airplane"),
        (.armCustomBypass, "alarm_arm_custom_bypass", "Custom", "slider.horizontal.3"),
    ]

    var body: some View {
        let alarm = app.store[card.entityID]
        let name = app.displayName(card)
        let state = alarm?.state ?? "unavailable"
        let disarmed = state == "disarmed"
        let hasCode = alarm?.codeFormat != nil
        let armNeedsCode = hasCode && (alarm?.codeArmRequired ?? true)
        let available = alarm?.isAvailable == true

        VStack(alignment: .leading, spacing: 18) {
            BackHeader(name)

            StateDial(
                systemImage: state == "triggered"
                    ? "exclamationmark.shield.fill" : (disarmed ? "shield" : "checkmark.shield.fill"),
                title: alarm.map(DeviceText.summary) ?? "Unavailable",
                subtitle: alarm?.changedBy.map { "By \($0)" } ?? alarm.flatMap { SinceText.text("Since", $0.lastChanged) },
                color: state == "triggered" ? Color(hex: 0xFF453A) : Color(hex: 0x30D158),
                active: available && !disarmed)

            if hasCode && (!disarmed || armNeedsCode) {
                CodeEntry(numeric: LockScreen.isNumeric(alarm?.codeFormat), code: $code)
            }

            if disarmed {
                let modes = Self.modes.filter { alarm?.alarmFeatures.contains($0.feature) == true }
                PanelSection("Arm") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                        ForEach(modes, id: \.service) { mode in
                            CapsuleButton(title: mode.title, systemImage: mode.icon) { send(mode.service) }
                        }
                    }
                }
                .disabled(!available || (armNeedsCode && code.isEmpty))
            } else {
                CapsuleButton(title: "Disarm", systemImage: "shield.slash") { send("alarm_disarm") }
                    .disabled(!available || (hasCode && code.isEmpty))
            }
        }
        .onDisappear { code = "" }
    }

    private func send(_ service: String) {
        var data: [String: JSONValue] = [:]
        if !code.isEmpty { data["code"] = .string(code) }
        app.call("alarm_control_panel", service, [card.entityID], data)
        code = ""
    }
}
