import HAKit
import SwiftUI

/// Device screen for a switch-like card (switch, input_boolean…).
struct SwitchScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card
    let section: CardSection

    private static let offAfterChoices: [(seconds: TimeInterval, label: String)] = [
        (0, "Off"), (15 * 60, "15 min"), (30 * 60, "30 min"), (3600, "1 h"), (7200, "2 h"),
    ]

    var body: some View {
        let state = app.store[card.entityID]
        let isOn = state?.isOn ?? false
        let name = app.displayName(card)

        VStack(alignment: .leading, spacing: 18) {
            BackHeader(name) {
                Text(section.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                BigToggle(isOn: isOn, name: name, systemImage: card.displayIcon) { app.toggle(card.entityID) }
                    .rollbackShake(card.entityID)
                    .disabled(state?.isAvailable != true)
                Text(state?.isAvailable == false ? "Unavailable" : (isOn ? "On" : "Off"))
                    .font(.system(size: 15, weight: .semibold))
                if let since = sinceText(state) {
                    Text(since)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            if let timerID = card.attachment(.offTimer)?.entityID, let timer = app.store.states[timerID] {
                turnOffAfter(timer: timer)
            }

            powerOnBehaviour

            let all = section.cards.filter { $0.kind == card.kind }.map(\.entityID)
            if all.count > 1 {
                PanelSection("All in \(section.title)") {
                    HStack(spacing: 8) {
                        CapsuleButton(title: "All on", systemImage: SFSymbol.filled(card.displayIcon)) { app.setOn(all, true) }
                        CapsuleButton(title: "All off", systemImage: card.displayIcon) { app.setOn(all, false) }
                    }
                }
            }
        }
    }

    // MARK: Turn off after

    private func turnOffAfter(timer: HAState) -> some View {
        let active = timer.state == "active" || timer.state == "paused"
        let selected: String = {
            guard active, let d = timer.timerDuration else { return "0" }
            return Self.offAfterChoices.first(where: { abs($0.seconds - d) < 1 }).map { String(Int($0.seconds)) } ?? ""
        }()
        return PanelSection("Turn off after") {
            SegmentedPills(
                options: Self.offAfterChoices.map { PillOption(value: String(Int($0.seconds)), label: $0.label) },
                selected: selected
            ) { value in
                let seconds = TimeInterval(value) ?? 0
                if seconds == 0 {
                    if active { app.cancelOffTimer(timerID: timer.entityID) }
                } else {
                    app.startOffTimer(switchID: card.entityID, timerID: timer.entityID, seconds: seconds)
                }
            }
            if active, let ends = timer.finishesAt, ends > .now {
                Text("Turns off in \(Text(timerInterval: Date.now...ends, countsDown: true))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: When power returns

    @ViewBuilder private var powerOnBehaviour: some View {
        if let selectID = card.attachment(.powerOnBehaviour)?.entityID, let select = app.store[selectID],
            !select.options.isEmpty
        {
            // Other cards in this section that share the same setting (e.g. one setting per hub).
            let sharedBy = section.cards.filter { $0.attachment(.powerOnBehaviour)?.entityID == selectID }.count
            PanelSection("When power returns") {
                SegmentedPills(
                    options: select.options.map { PillOption(value: $0, label: Self.powerOnLabel($0)) },
                    selected: select.state
                ) { app.selectOption(selectID, $0) }
                .rollbackShake(selectID)
                if sharedBy > 1 {
                    Text("Applies to all \(sharedBy) switches in \(section.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Friendly names for common power-on behaviour values (Tuya numbers, Zigbee words).
    static func powerOnLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "0", "off": "Off"
        case "1", "on": "On"
        case "2", "previous", "restore", "memory", "last_state": "Restore"
        case "toggle": "Toggle"
        default: value.capitalized
        }
    }

    private func sinceText(_ state: HAState?) -> String? {
        guard let state, state.isAvailable, state.lastChanged > .distantPast else { return nil }
        let d = state.lastChanged
        let when = d.formatted(date: Calendar.current.isDateInToday(d) ? .omitted : .abbreviated, time: .shortened)
        return "\(state.isOn ? "On" : "Off") since \(when)"
    }
}

/// Tall Control Center style toggle that fills white from the bottom.
struct BigToggle: View {
    let isOn: Bool
    let name: String
    var systemImage = "lightbulb"
    let action: () -> Void

    private let size = CGSize(width: 112, height: 196)
    private let radius: CGFloat = 32

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.track)
                Rectangle()
                    .fill(Theme.onFill)
                    .frame(height: isOn ? size.height : 0)
                Image(systemName: systemImage)
                    .symbolVariant(isOn ? .fill : .none)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(isOn ? Theme.amber : Color.secondary)
                    .shadow(color: isOn ? Theme.amber.opacity(0.7) : .clear, radius: 10)
                    .padding(.bottom, 30)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5))
            .contentShape(.rect(cornerRadius: radius))
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: isOn)
        .accessibilityLabel(name)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
