import HAKit
import SwiftUI

/// Fans: on/off, speed, presets, oscillation and direction when supported.
struct FanScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card
    let section: CardSection

    var body: some View {
        let fan = app.store[card.entityID]
        let f = fan?.fanFeatures ?? []
        let isOn = fan?.isOn ?? false
        let name = app.displayName(card)
        let id = card.entityID

        VStack(alignment: .leading, spacing: 18) {
            BackHeader(name) {
                Text(section.title).font(.system(size: 12)).foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                BigToggle(isOn: isOn, name: name, systemImage: DeviceIcon.symbol(card, fan)) { app.toggle(id) }
                    .rollbackShake(id)
                    .disabled(fan?.isAvailable != true)
                Text(fan.map(DeviceText.summary) ?? "Unavailable")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)

            if f.contains(.setSpeed), let fan, fan.isAvailable {
                PanelSection("Speed") {
                    LiveSlider(
                        value: isOn ? Double(fan.fanPercentage ?? 0) / 100 : 0,
                        systemImage: "wind",
                        accessibilityName: "Speed",
                        label: { $0 < 0.005 ? "Off" : "\(Int(($0 * 100).rounded()))%" }
                    ) { [app] v in
                        let step = max(1, fan.fanPercentageStep)
                        let pct = Int((v * 100 / step).rounded() * step)
                        if pct == 0 {
                            app.setOn([id], false)
                        } else {
                            app.call("fan", "set_percentage", [id], ["percentage": .integer(min(100, pct))])
                        }
                    }
                }
            }

            if f.contains(.presetMode), let fan, fan.isAvailable, !fan.presetModes.isEmpty {
                PanelSection("Mode") {
                    ChoicePills(
                        options: fan.presetModes.map { PillOption(value: $0, label: DeviceText.label($0)) },
                        selected: isOn ? fan.presetMode : nil
                    ) { app.call("fan", "set_preset_mode", [id], ["preset_mode": .string($0)]) }
                }
            }

            if fan?.isAvailable == true, f.contains(.oscillate) || f.contains(.direction) {
                VStack(spacing: 8) {
                    if f.contains(.oscillate) {
                        ToggleRow(title: "Oscillate", systemImage: "arrow.left.and.right", isOn: fan?.oscillating ?? false) {
                            app.call("fan", "oscillate", [id], ["oscillating": .bool(!(fan?.oscillating ?? false))])
                        }
                    }
                    if f.contains(.direction) {
                        SegmentedPills(
                            options: [PillOption(value: "forward", label: "Forward"), PillOption(value: "reverse", label: "Reverse")],
                            selected: fan?.fanDirection
                        ) { app.call("fan", "set_direction", [id], ["direction": .string($0)]) }
                    }
                }
            }

            let all = section.cards.filter { $0.kind == .fan }.map(\.entityID)
            if all.count > 1 {
                PanelSection("All in \(section.title)") {
                    HStack(spacing: 8) {
                        CapsuleButton(title: "All on", systemImage: "fan.fill") { app.setOn(all, true) }
                        CapsuleButton(title: "All off", systemImage: "fan") { app.setOn(all, false) }
                    }
                }
            }
        }
    }
}
