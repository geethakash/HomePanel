import HAKit
import SwiftUI

/// A select or input_select: its options as a list.
struct SelectScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card

    var body: some View {
        let select = app.store[card.entityID]
        VStack(alignment: .leading, spacing: 14) {
            BackHeader(app.displayName(card))
            VStack(spacing: 2) {
                ForEach(select?.options ?? [], id: \.self) { option in
                    OptionRow(title: option, isSelected: option == select?.state) {
                        let domain = card.entityID.hasPrefix("input_select.") ? "input_select" : "select"
                        app.store.setOptimistic(card.entityID, state: option)
                        app.call(domain, "select_option", [card.entityID], ["option": .string(option)])
                    }
                }
            }
            .padding(4)
            .background(TileBackground(radius: 14))
            .rollbackShake(card.entityID)
            .disabled(select?.isAvailable != true)
        }
    }
}

/// A number or input_number: a big value with − / + and a slider.
struct NumberScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card

    @State private var pending: Double?
    @State private var debouncer = Debouncer(delay: .milliseconds(500))

    var body: some View {
        let number = app.store[card.entityID]
        let lo = number?.minValue ?? 0
        let hi = max(lo + 1, number?.maxValue ?? 100)
        let step = number?.step ?? 1
        let value = pending ?? number?.numericState ?? lo
        let unit = number?.unit.map { " \($0)" } ?? ""

        VStack(alignment: .leading, spacing: 18) {
            BackHeader(app.displayName(card))

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    RoundIconButton(systemImage: "minus", label: "Decrease") { set(value - step, lo, hi, step) }
                        .disabled(value <= lo)
                    Spacer()
                    Text(Self.format(value, step: step) + unit)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: value))
                    Spacer()
                    RoundIconButton(systemImage: "plus", label: "Increase") { set(value + step, lo, hi, step) }
                        .disabled(value >= hi)
                }
                .padding(.horizontal, 12)

                LiveSlider(
                    value: (value - lo) / (hi - lo),
                    accessibilityName: app.displayName(card),
                    label: { Self.format(lo + $0 * (hi - lo), step: step) + unit }
                ) { [lo, hi, step] fraction in
                    set(lo + fraction * (hi - lo), lo, hi, step)
                }
            }
            .disabled(number?.isAvailable != true)
        }
        .onChange(of: number?.numericState) { _, _ in pending = nil }
    }

    private func set(_ raw: Double, _ lo: Double, _ hi: Double, _ step: Double) {
        let snapped = min(hi, max(lo, lo + ((raw - lo) / step).rounded() * step))
        pending = snapped
        let domain = card.entityID.hasPrefix("input_number.") ? "input_number" : "number"
        debouncer.call { [app, id = card.entityID] in app.call(domain, "set_value", [id], ["value": .number(snapped)]) }
    }

    static func format(_ v: Double, step: Double) -> String {
        step >= 1 ? v.formatted(.number.precision(.fractionLength(0))) : v.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// Sensors and binary sensors: the reading, when it changed, and what kind of sensor it is.
struct SensorScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card

    var body: some View {
        let sensor = app.store[card.entityID]
        VStack(alignment: .leading, spacing: 18) {
            BackHeader(app.displayName(card))
            StateDial(
                systemImage: DeviceIcon.symbol(card, sensor),
                title: sensor.map(DeviceText.summary) ?? "Unavailable",
                subtitle: sensor.flatMap { SinceText.text("Changed", $0.lastChanged) },
                color: Theme.amber,
                active: sensor.map(DeviceText.isActive) ?? false)
            if let sensor {
                VStack(spacing: 2) {
                    if let deviceClass = sensor.deviceClass {
                        detail("Type", DeviceText.label(deviceClass))
                    }
                    detail("Entity", sensor.entityID)
                    if sensor.lastUpdated > .distantPast {
                        detail("Updated", sensor.lastUpdated.formatted(date: .abbreviated, time: .standard))
                    }
                }
                .padding(4)
                .background(TileBackground(radius: 14))
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}
