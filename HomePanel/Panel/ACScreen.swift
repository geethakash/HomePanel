import HAKit
import SwiftUI

/// Device screen for a climate card. Each control shows only when the unit supports it: modes
/// from `hvac_modes`, fan speed and air flow from attached selects or the climate entity's own
/// fan, swing and preset modes, and feature tiles from attached switches.
///
/// Many A/C units beep on every command, so the target temperature is debounced and nothing
/// is sent unless you tap.
struct ACScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card

    @State private var pendingTarget: Double?
    @State private var pendingClear: Task<Void, Never>?
    @State private var tempDebouncer = Debouncer(delay: .milliseconds(700))

    private var climateID: String { card.entityID }

    var body: some View {
        let climate = app.store[climateID]
        let mode = climate?.state ?? "off"
        let isOn = mode != "off" && climate?.isAvailable == true
        let name = app.displayName(card)

        VStack(alignment: .leading, spacing: 18) {
            BackHeader(name) {
                PowerButton(isOn: isOn, label: name) {
                    app.setClimatePower(climateID, on: !isOn)
                }
                .rollbackShake(climateID)
                .disabled(climate?.isAvailable != true)
            }

            ACUnitCard(state: ACVisualState(store: app.store, card: card, room: app.currentRoom))

            if let climate, climate.temperature == nil, let low = climate.targetTempLow, let high = climate.targetTempHigh {
                TemperatureRange(climateID: climateID, low: low, high: high, isOn: isOn, climate: climate)
            } else {
                targetTemperature(climate, isOn: isOn)
            }

            let modes = modeOptions(climate)
            if !modes.isEmpty {
                PanelSection("Mode") {
                    ChoicePills(options: modes, selected: isOn ? mode : nil) {
                        app.setHVACMode(climateID, $0)
                    }
                }
                .disabled(climate?.isAvailable != true)
            }

            fanSpeed(climate)

            let airflow = ACOption.allCases.compactMap { option in
                option.setting(card: card, store: app.store).map { (option, $0) }
            }
            if !airflow.isEmpty {
                PanelSection("Air flow & comfort") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gridSpacing), count: 4),
                        spacing: Theme.gridSpacing
                    ) {
                        ForEach(airflow, id: \.0) { option, setting in
                            AirflowTile(option: option, card: card, value: setting.current)
                                .modifier(ShakeIfSelect(source: setting.source))
                        }
                    }
                }
            }

            let features = card.attachments(.feature)
            if !features.isEmpty {
                PanelSection("Features") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gridSpacing), count: 3),
                        spacing: Theme.gridSpacing
                    ) {
                        ForEach(features, id: \.entityID) { feature in
                            FeatureTile(feature: feature)
                        }
                    }
                }
            }
        }
        .onChange(of: climate?.temperature) { _, newValue in
            if let pendingTarget, let newValue, abs(pendingTarget - newValue) < 0.01 { self.pendingTarget = nil }
        }
        .onDisappear { tempDebouncer.flush() }
    }

    // MARK: Fan speed

    /// A fan-speed select attachment (used instead of the climate's own fan mode, which some
    /// units handle badly), or the climate entity's `fan_modes`.
    @ViewBuilder
    private func fanSpeed(_ climate: HAState?) -> some View {
        if let selectID = card.attachment(.fanSpeed)?.entityID, let fan = app.store[selectID], !fan.options.isEmpty {
            PanelSection("Fan speed") {
                ChoicePills(
                    options: fan.options.map { PillOption(value: $0, label: Self.shortFan($0)) },
                    selected: fan.state, maxSegments: 6
                ) { app.selectOption(selectID, $0) }
                .rollbackShake(selectID)
            }
            .disabled(!fan.isAvailable)
        } else if let climate, !climate.fanModes.isEmpty {
            PanelSection("Fan speed") {
                ChoicePills(
                    options: climate.fanModes.map { PillOption(value: $0, label: Self.shortFan(ACOption.label($0))) },
                    selected: climate.fanMode, maxSegments: 6
                ) { app.setFanMode(climateID, $0) }
            }
            .disabled(!climate.isAvailable)
        }
    }

    private static func shortFan(_ name: String) -> String {
        name == "Medium" ? "Med" : name
    }

    // MARK: Target temperature

    private func targetTemperature(_ climate: HAState?, isOn: Bool) -> some View {
        let range = (climate?.minTemp ?? 7)...(climate?.maxTemp ?? 35)
        let step = climate?.targetTempStep ?? 1
        let shown = pendingTarget ?? climate?.temperature
        let subtitle = Self.subtitle(climate, app: app)

        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                RoundIconButton(systemImage: "minus", label: "Lower temperature") {
                    adjust(by: -step, from: shown, in: range)
                }
                .disabled(!isOn || (shown ?? range.lowerBound) <= range.lowerBound)
                Spacer()
                Text(shown.map { Self.format($0, step: step) } ?? "–")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: shown ?? 0))
                    .animation(.snappy, value: shown)
                    .opacity(isOn ? 1 : 0.4)
                    .accessibilityLabel("Target temperature")
                    .accessibilityValue(shown.map { "\(Self.format($0, step: step)) degrees" } ?? "unknown")
                Spacer()
                RoundIconButton(systemImage: "plus", label: "Raise temperature") {
                    adjust(by: step, from: shown, in: range)
                }
                .disabled(!isOn || (shown ?? range.upperBound) >= range.upperBound)
            }
            .padding(.horizontal, 18)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func adjust(by delta: Double, from current: Double?, in range: ClosedRange<Double>) {
        let base = current ?? 24
        let new = min(range.upperBound, max(range.lowerBound, base + delta))
        guard new != base else { return }
        pendingTarget = new
        pendingClear?.cancel()
        tempDebouncer.call { [app, climateID] in
            app.setTemperature(climateID, new)
        }
        // If HA never confirms, fall back to its value.
        pendingClear = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            pendingTarget = nil
        }
    }

    static func format(_ t: Double, step: Double) -> String {
        step < 1 ? t.formatted(.number.precision(.fractionLength(1))) + "°" : "\(Int(t.rounded()))°"
    }

    /// "Cool · Cooling · room 28°C"
    @MainActor
    static func subtitle(_ climate: HAState?, app: AppModel) -> String {
        var parts = [HVACMode.name(climate?.state ?? "off")]
        if let action = climate?.hvacAction.flatMap(HVACMode.actionName), climate?.state != "off" {
            parts.append(action)
        }
        if let room = climate?.currentTemperature ?? HeaderReadout.roomTemperature(app.currentRoom, store: app.store) {
            parts.append("room \(Int(room.rounded()))\(app.temperatureUnit)")
        }
        return parts.joined(separator: " · ")
    }

    private func modeOptions(_ climate: HAState?) -> [PillOption] {
        HVACMode.sorted(climate?.hvacModes ?? []).map { PillOption(value: $0, label: HVACMode.name($0)) }
    }
}

// MARK: - Air flow & comfort

/// Where a climate setting lives: a select attached to the card, or the climate entity's own
/// attribute (swing, horizontal swing or preset mode).
struct ClimateSetting: Equatable {
    enum Source: Equatable {
        case select(String)
        case climate(service: String, key: String)
    }

    let source: Source
    let options: [String]
    let current: String?
    let isAvailable: Bool
}

/// The settings that open their own option screen from a tile.
enum ACOption: String, CaseIterable, Hashable {
    case upDown, leftRight, preset, sleep, gen

    /// The card attachment that holds this setting's select.
    var role: Attachment.Role {
        switch self {
        case .upDown: .swingVertical
        case .leftRight: .swingHorizontal
        case .preset: .preset
        case .sleep: .sleep
        case .gen: .powerLimit
        }
    }

    /// The setting for this card: its attached select, else the climate entity's own modes.
    @MainActor
    func setting(card: Card, store: EntityStore) -> ClimateSetting? {
        if let id = card.attachment(role)?.entityID {
            guard let select = store[id], !select.options.isEmpty else { return nil }
            return ClimateSetting(
                source: .select(id), options: select.options, current: select.state, isAvailable: select.isAvailable)
        }
        guard let climate = store[card.entityID] else { return nil }
        let found: (options: [String], current: String?, service: String, key: String)? =
            switch self {
            case .upDown: (climate.swingModes, climate.swingMode, "set_swing_mode", "swing_mode")
            case .leftRight:
                (climate.swingHorizontalModes, climate.swingHorizontalMode, "set_swing_horizontal_mode", "swing_horizontal_mode")
            case .preset: (climate.presetModes, climate.presetMode, "set_preset_mode", "preset_mode")
            case .sleep, .gen: nil
            }
        guard let found, !found.options.isEmpty else { return nil }
        return ClimateSetting(
            source: .climate(service: found.service, key: found.key), options: found.options,
            current: found.current, isAvailable: climate.isAvailable)
    }

    /// Tile name; the attachment's own name wins (e.g. "GEN").
    func name(_ card: Card) -> String {
        if let name = card.attachment(role)?.name { return name }
        switch self {
        case .upDown: return "Up-down"
        case .leftRight: return "Left-right"
        case .preset: return "Preset"
        case .sleep: return "Sleep"
        case .gen: return "Power limit"
        }
    }

    func title(_ card: Card) -> String {
        switch self {
        case .upDown: "Up-down air flow"
        case .leftRight: "Left-right air flow"
        case .preset: "Preset"
        case .sleep: "Sleep mode"
        case .gen: card.attachment(role)?.name.map { "\($0) mode" } ?? "Power limit"
        }
    }

    var explanation: String {
        switch self {
        case .upDown: "Where the vertical louver points. Swing sweeps it, fixed holds one angle."
        case .leftRight: "Which way the side blades push the air. Swing sweeps them, fixed holds one direction."
        case .preset: "The unit's built-in presets, like Eco, Boost or Sleep."
        case .sleep: "Gently shifts the temperature overnight for more comfortable sleep."
        case .gen: "Caps the A/C's maximum power draw."
        }
    }

    var systemImage: String {
        switch self {
        case .upDown: "arrow.up.and.down"
        case .leftRight: "arrow.left.and.right"
        case .preset: "star"
        case .sleep: "moon"
        case .gen: "bolt"
        }
    }

    /// Grouped rows for the option screen.
    func groups(_ options: [String]) -> [(title: String, options: [String])] {
        switch self {
        case .upDown, .leftRight:
            let swing = options.filter { Airflow.isSweep($0) }
            let fixed = options.filter { !Airflow.isSweep($0) }
            return [("Swing", swing), ("Fixed", fixed)].filter { !$0.1.isEmpty }
        case .preset: return [("Presets", options)]
        case .sleep: return [("Sleep curve", options)]
        case .gen: return [("Power limit", options)]
        }
    }

    /// "Active" = swinging, or anything other than off / none.
    func isActive(_ value: String?) -> Bool {
        switch self {
        case .upDown, .leftRight: value.map { Airflow.isSweep($0) } ?? false
        case .preset, .sleep, .gen: !Airflow.isOff(value)
        }
    }

    /// Short value for the tile ("Swing", "Middle", "Off", "Level 2").
    func shortValue(_ value: String?) -> String {
        switch self {
        case .upDown, .leftRight: return Airflow.shortName(value)
        case .preset, .sleep, .gen:
            guard let value, value != "unknown", value != "unavailable" else { return "–" }
            return Airflow.isOff(value) ? "Off" : Self.label(value)
        }
    }

    /// "fan_only" → "Fan only", "eco" → "Eco"; names that are already capitalised stay as they are.
    static func label(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalizedFirst
    }
}

private struct AirflowTile: View {
    @Environment(AppModel.self) private var app
    let option: ACOption
    let card: Card
    let value: String?

    var body: some View {
        let active = option.isActive(value)
        Button {
            app.push(.climateOption(card.id, option))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(height: 18)
                Spacer(minLength: 0)
                Text(option.name(card))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(option.shortValue(value))
                    .font(.system(size: 10))
                    .foregroundStyle(active ? Theme.onSecondaryText : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(active ? Theme.onText : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 76)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(TileBackground(isOn: active, radius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(PressableStyle())
        .animation(Theme.spring, value: active)
        .accessibilityLabel("\(option.title(card)), \(value ?? "unknown")")
        .accessibilityHint("Opens \(option.title(card)) options")
    }
}

/// Pushed from an Air flow & comfort tile. Picking a row applies it and stays here.
struct ACOptionScreen: View {
    @Environment(AppModel.self) private var app
    let card: Card
    let option: ACOption

    var body: some View {
        let setting = option.setting(card: card, store: app.store)
        let options = setting?.options ?? []

        VStack(alignment: .leading, spacing: 16) {
            BackHeader(app.displayName(card))

            ACUnitCard(state: ACVisualState(store: app.store, card: card, room: app.currentRoom))

            VStack(alignment: .leading, spacing: 4) {
                Text(option.title(card))
                    .font(.system(size: 15, weight: .semibold))
                Text(option.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(option.groups(options), id: \.title) { group in
                PanelSection(group.title) {
                    VStack(spacing: 2) {
                        ForEach(group.options, id: \.self) { value in
                            OptionRow(title: ACOption.label(value), isSelected: value == setting?.current) {
                                if let setting { app.apply(setting, value, climateID: card.entityID) }
                            }
                        }
                    }
                    .padding(4)
                    .background(TileBackground(radius: 14))
                    .modifier(ShakeIfSelect(source: setting?.source))
                }
            }
            .disabled(setting?.isAvailable != true)
        }
    }
}

// MARK: - Features

private struct FeatureTile: View {
    @Environment(AppModel.self) private var app
    let feature: Attachment

    var body: some View {
        let state = app.store[feature.entityID]
        let name = feature.name ?? state?.friendlyName ?? feature.entityID
        let isOn = state?.isOn ?? false
        Button {
            app.toggle(feature.entityID)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: feature.icon ?? "switch.2")
                    .symbolVariant(isOn ? .fill : .none)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.onText : Color.secondary)
                    .frame(height: 18)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isOn ? Theme.onText : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(TileBackground(isOn: isOn, radius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(PressableStyle())
        .disabled(state?.isAvailable != true)
        .opacity(state?.isAvailable == false ? 0.5 : 1)
        .rollbackShake(feature.entityID)
        .animation(Theme.spring, value: isOn)
        .accessibilityLabel(name)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// 44 pt round − / + button.
struct RoundIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.track))
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Heat/cool range

/// Low and high setpoints for units that hold a range (heat/cool mode).
private struct TemperatureRange: View {
    @Environment(AppModel.self) private var app
    let climateID: String
    let low: Double
    let high: Double
    let isOn: Bool
    let climate: HAState

    @State private var pending: (low: Double, high: Double)?
    @State private var debouncer = Debouncer(delay: .milliseconds(700))
    @State private var clearTask: Task<Void, Never>?

    var body: some View {
        let step = climate.targetTempStep ?? 0.5
        let range = (climate.minTemp ?? 7)...(climate.maxTemp ?? 35)
        let shown = pending ?? (low, high)

        VStack(spacing: 6) {
            HStack(spacing: 10) {
                setpoint("Heat to", value: shown.low, step: step) { delta in
                    change(low: min(shown.high - step, max(range.lowerBound, shown.low + delta)), high: shown.high)
                }
                setpoint("Cool to", value: shown.high, step: step) { delta in
                    change(low: shown.low, high: max(shown.low + step, min(range.upperBound, shown.high + delta)))
                }
            }
            Text(ACScreen.subtitle(climate, app: app))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .disabled(!isOn)
        .onDisappear { debouncer.flush() }
    }

    private func setpoint(_ title: String, value: Double, step: Double, adjust: @escaping (Double) -> Void)
        -> some View
    {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                RoundIconButton(systemImage: "minus", label: "Lower \(title.lowercased())") { adjust(-step) }
                Text(ACScreen.format(value, step: step))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .frame(minWidth: 54)
                    .opacity(isOn ? 1 : 0.4)
                RoundIconButton(systemImage: "plus", label: "Raise \(title.lowercased())") { adjust(step) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(TileBackground())
    }

    private func change(low: Double, high: Double) {
        withAnimation(.snappy) { pending = (low, high) }
        debouncer.call { [app, climateID] in app.setTemperatureRange(climateID, low: low, high: high) }
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            pending = nil
        }
    }
}

/// Rollback shake for settings backed by a select (the climate's own modes aren't optimistic).
private struct ShakeIfSelect: ViewModifier {
    let source: ClimateSetting.Source?

    func body(content: Content) -> some View {
        if case .select(let id) = source {
            content.rollbackShake(id)
        } else {
            content
        }
    }
}
