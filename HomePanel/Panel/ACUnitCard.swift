import HAKit
import SwiftUI

/// Everything the A/C unit drawing depends on, derived from live state.
struct ACVisualState: Equatable {
    var mode: String = "off"
    var target: Double?
    var roomTemperature: Double?
    var displayOn = true
    var upDown: Airflow.Position = .fixed(0)
    var leftRight: Airflow.Position = .fixed(0)
    var upDownLabel = "–"
    var leftRightLabel = "–"
    var fanSpeed = "Auto"
    var fan: FanLevel = .auto
    var eco = false
    var health = false
    var softWind = false
    var available = false

    var isOn: Bool { mode != "off" && available }

    @MainActor
    init(store: EntityStore, card: Card, room: Room?) {
        let climate = store[card.entityID]
        /// A feature switch whose name contains `keyword` (e.g. "display", "eco").
        func feature(_ keyword: String) -> Bool? {
            card.attachments(.feature)
                .first { ($0.name ?? store[$0.entityID]?.friendlyName ?? $0.entityID).lowercased().contains(keyword) }
                .map { store[$0.entityID]?.isOn ?? false }
        }
        mode = climate?.state ?? "off"
        available = climate?.isAvailable ?? false
        target = climate?.temperature ?? climate?.targetTempHigh
        roomTemperature = climate?.currentTemperature ?? HeaderReadout.roomTemperature(room, store: store)
        displayOn = feature("display") ?? true

        if let v = ACOption.upDown.setting(card: card, store: store) {
            upDown = Airflow.position(of: v.current, among: v.options, axis: .vertical)
            upDownLabel = Airflow.shortName(v.current)
            // A single climate swing mode ("both", "horizontal") also drives the side blades.
            if case .climate = v.source, ACOption.leftRight.setting(card: card, store: store) == nil {
                leftRight = Airflow.position(of: v.current, among: v.options, axis: .horizontal)
            }
        }
        if let h = ACOption.leftRight.setting(card: card, store: store) {
            leftRight = Airflow.position(of: h.current, among: h.options, axis: .horizontal)
            leftRightLabel = Airflow.shortName(h.current)
        }
        let fanName = card.attachment(.fanSpeed).flatMap { store[$0.entityID]?.state } ?? climate?.fanMode
        if let fanName, fanName != "unknown" {
            fanSpeed = fanName.capitalizedFirst
            fan = FanLevel(fanName)
        }
        eco = feature("eco") ?? (climate?.presetMode?.lowercased() == "eco")
        health = feature("health") ?? feature("ioniz") ?? false
        softWind = feature("soft") ?? false
    }
}

/// The A/C unit card shown on the A/C screen and its option screens.
struct ACUnitCard: View {
    let state: ACVisualState

    var body: some View {
        ACAnimationView(state: state)
            .frame(maxWidth: .infinity)
            .frame(height: 152)
            .background(TileBackground())
            .clipShape(.rect(cornerRadius: Theme.tileRadius, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard state.available else { return "A/C unavailable" }
        guard state.isOn else { return "A/C off" }
        return "A/C \(HVACMode.name(state.mode)), fan \(state.fanSpeed), air flow \(state.upDownLabel), \(state.leftRightLabel)"
    }
}
