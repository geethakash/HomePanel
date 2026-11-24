import HAKit
import SwiftUI

/// The current room: a header, then each section of cards from the layout config.
struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focus: HomeFocus?

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 18) {
            HomeHeader(room: app.currentRoom, showingRooms: $app.showingRooms)

            if app.showingRooms {
                RoomList()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let room = app.currentRoom {
                if app.editing {
                    Text("Drag tiles to reorder. Use the eye to hide or show one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                ForEach(room.sections) { section in
                    if app.editing || !section.visibleCards.isEmpty {
                        PanelSection(section.title) {
                            SectionContent(section: section, room: room, editing: app.editing, focus: $focus)
                        }
                    }
                }
                if room.sections.isEmpty {
                    Text("This room is empty. Add devices in Settings → Rooms.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No rooms yet. Set up your panel in Settings.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    CapsuleButton(title: "Open Settings", systemImage: "gearshape") { app.showSettings() }
                }
            }
        }
        // Keyboard: the screen itself takes focus so arrow keys work as soon as the panel opens.
        .focusable(interactions: .activate)
        .focused($focus, equals: .container)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear { if focus == nil { focus = .container } }
    }

    /// Visible tiles in panel order, with where each sits (for arrow-key moves).
    private var order: [(id: UUID, section: Int, style: CardSection.Style)] {
        guard let room = app.currentRoom, !app.showingRooms else { return [] }
        return room.sections.enumerated().flatMap { index, section in
            (app.editing ? section.cards : section.visibleCards).map { ($0.id, index, section.style) }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let list = order
        guard !list.isEmpty else { return .ignored }
        guard case .card(let current) = focus, let i = list.firstIndex(where: { $0.id == current }) else {
            // Nothing focused yet: any arrow key starts at the first tile.
            if [.leftArrow, .rightArrow, .upArrow, .downArrow].contains(press.key) {
                focus = .card(list[0].id)
                return .handled
            }
            return .ignored
        }
        let here = list[i]
        if app.editing, press.modifiers.contains(.option), [.leftArrow, .rightArrow].contains(press.key) {
            app.nudgeCard(here.id, by: press.key == .leftArrow ? -1 : 1)
            return .handled
        }
        switch press.key {
        case .leftArrow: move(to: max(0, i - 1), list)
        case .rightArrow: move(to: min(list.count - 1, i + 1), list)
        case .upArrow, .downArrow:
            let down = press.key == .downArrow
            let step = here.style == .grid ? 3 : 1
            let j = down ? i + step : i - step
            if list.indices.contains(j), list[j].section == here.section {
                move(to: j, list)
            } else if down, let next = list.firstIndex(where: { $0.section > here.section }) {
                move(to: next, list)
            } else if !down, let prev = list.lastIndex(where: { $0.section < here.section }) {
                move(to: prev, list)
            }
        case .space:
            guard !app.editing, let card = app.config.config.locate(card: here.id)?.card else { return .ignored }
            app.keyActivate(card)
        case .return:
            if app.editing { return .ignored }  // Return is "Done" in edit mode
            guard let card = app.config.config.locate(card: here.id)?.card else { return .ignored }
            if app.hasScreen(card) { app.push(.card(card.id)) } else { app.keyActivate(card) }
        default:
            return .ignored
        }
        return .handled
    }

    private func move(to index: Int, _ list: [(id: UUID, section: Int, style: CardSection.Style)]) {
        focus = .card(list[index].id)
    }
}

enum HomeFocus: Hashable {
    case container
    case card(UUID)
}

private struct SectionContent: View {
    @Environment(AppModel.self) private var app
    let section: CardSection
    let room: Room
    var editing = false
    var focus: FocusState<HomeFocus?>.Binding

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.gridSpacing), count: 3)

    var body: some View {
        let cards = editing ? section.cards : section.visibleCards
        Group {
            switch section.style {
            case .grid:
                LazyVGrid(columns: columns, spacing: Theme.gridSpacing) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        CardTile(card: card, room: room).editable(card, index: index, editing: editing)
                            .keyFocus(card.id, focus)
                    }
                }
            case .rows:
                VStack(spacing: Theme.gridSpacing) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        CardTile(card: card, room: room).editable(card, index: index, editing: editing)
                            .keyFocus(card.id, focus)
                    }
                }
            case .pills:
                FlowLayout(spacing: 6) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        ActionPill(card: card).editable(card, index: index, editing: editing)
                            .keyFocus(card.id, focus, radius: 16)
                    }
                }
            }
        }
        .overlay {
            if editing && cards.isEmpty {
                Text("Drop a tile here")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.tertiary))
            }
        }
        .frame(minHeight: editing && cards.isEmpty ? 44 : nil)
        .modifier(SectionDropTarget(section: section, editing: editing, isEmpty: cards.isEmpty))
    }
}

/// In edit mode, dropping a tile on a section (not on another tile) moves it to the end.
/// Only attached while editing: drop targets are AppKit views, which also can't be snapshotted.
private struct SectionDropTarget: ViewModifier {
    @Environment(AppModel.self) private var app
    let section: CardSection
    let editing: Bool
    let isEmpty: Bool

    func body(content: Content) -> some View {
        if editing {
            content.dropDestination(for: String.self) { items, _ in
                guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                if !section.cards.contains(where: { $0.id == id }) || isEmpty {
                    app.moveCard(id, toEndOf: section.id)
                }
                return true
            }
        } else {
            content
        }
    }
}

/// Picks the tile for a card's kind.
private struct CardTile: View {
    let card: Card
    let room: Room

    var body: some View {
        switch card.kind {
        case .light: LightTile(card: card)
        case .climate: ClimateRow(card: card, room: room)
        default: DeviceTile(card: card)
        }
    }
}

/// Tile for switches, fans, covers, media, locks, alarms, sensors, selects, numbers and actions.
/// The icon does the device's quick action (`AppModel.quickAction`); the rest opens its screen.
private struct DeviceTile: View {
    @Environment(AppModel.self) private var app
    let card: Card

    var body: some View {
        let state = app.store[card.entityID]
        let name = app.displayName(card)
        let quick = app.quickAction(card)
        let color = DeviceIcon.onColor(card, state)
        EntityTile(
            title: name,
            subtitle: state.map(DeviceText.summary) ?? "–",
            systemImage: DeviceIcon.symbol(card, state),
            isOn: state.map(DeviceText.isActive) ?? false,
            isAvailable: state?.isAvailable ?? false,
            onColor: color.color,
            onColorIsLight: color.isLight,
            iconActionLabel: quick?.label(name) ?? "Open \(name)",
            onToggle: {
                if let quick { app.perform(quick, card) } else { app.push(.card(card.id)) }
            },
            onOpen: {
                if app.hasScreen(card) { app.push(.card(card.id)) } else if let quick { app.perform(quick, card) }
            }
        )
        .rollbackShake(card.entityID)
    }
}

private struct LightTile: View {
    @Environment(AppModel.self) private var app
    let card: Card

    var body: some View {
        let state = app.store[card.entityID]
        let isOn = state?.isOn ?? false
        let hasColor = state?.rgb != nil || state?.colorMode == "color_temp"
        let rgb = state?.colorMode == "color_temp" ? LightScreen.displayRGB(state) : (state?.rgb ?? [255, 214, 10])
        EntityTile(
            title: app.displayName(card),
            subtitle: isOn ? (state?.brightnessPct.map { "\($0)%" } ?? "On") : "Off",
            systemImage: card.displayIcon,
            isOn: isOn,
            isAvailable: state?.isAvailable ?? false,
            onColor: Color(rgb: rgb),
            // Real colours pick a readable symbol; the default yellow uses a white bulb.
            onColorIsLight: hasColor && RGB.luminance(rgb) > 0.6,
            onToggle: { app.toggle(card.entityID) },
            onOpen: { app.push(.card(card.id)) }
        )
        .rollbackShake(card.entityID)
    }
}

/// Small pill for scenes, scripts and buttons.
private struct ActionPill: View {
    @Environment(AppModel.self) private var app
    let card: Card

    var body: some View {
        Button {
            app.activate(card.entityID)
        } label: {
            Label(app.displayName(card), systemImage: card.displayIcon)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(card.kind == .scene || card.kind == .script || card.kind == .button ? "Runs it" : "")
    }
}

// MARK: - Header

private struct HomeHeader: View {
    @Environment(AppModel.self) private var app
    let room: Room?
    @Binding var showingRooms: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                roomTitle
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusColor.opacity(0.8), radius: 3)
                    Text(app.store.status.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
            if app.editing {
                editControls
            } else {
                readouts
                headerButton("pencil", label: "Edit this room") { app.setEditing(true) }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(room == nil)
                    .padding(.leading, 6)
            }
        }
    }

    private var readouts: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ForEach(Array((room?.headerSensors ?? []).prefix(2).enumerated()), id: \.element) { index, id in
                if let sensor = app.store[id], let value = sensor.numericState {
                    Label(HeaderReadout.text(value, unit: sensor.unit), systemImage: HeaderReadout.icon(sensor))
                        .font(.system(size: index == 0 ? 13 : 11, weight: index == 0 ? .semibold : .regular))
                        .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var editControls: some View {
        HStack(spacing: 6) {
            Button {
                app.setEditing(false)
                app.showSettings(tab: "rooms")
            } label: {
                Text("Customise…")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            Button {
                app.setEditing(false)
            } label: {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.onText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.onFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.return, modifiers: [])
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    /// The room name; with more than one room it opens the room list.
    @ViewBuilder private var roomTitle: some View {
        let title = Text(room?.name ?? "HomePanel").font(.system(size: 20, weight: .bold))
        if app.config.config.rooms.count > 1 && !app.editing {
            Button {
                withAnimation(Theme.spring) { showingRooms.toggle() }
            } label: {
                HStack(spacing: 5) {
                    title
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showingRooms ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Room, \(room?.name ?? "none")")
            .accessibilityHint(showingRooms ? "Closes the room list" : "Shows the room list")
        } else {
            title
        }
    }

    private var statusColor: Color {
        switch app.store.status {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected, .needsSetup: .gray
        case .notOnHomeNetwork, .authFailed, .error: .red
        }
    }
}

enum HeaderReadout {
    static func text(_ value: Double, unit: String?) -> String {
        let unit = unit ?? ""
        if unit == "%" { return "\(Int(value.rounded()))%" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + unit
    }

    static func icon(_ sensor: HAState) -> String {
        switch sensor.deviceClass {
        case "temperature": "thermometer.medium"
        case "humidity": "humidity"
        case "power", "energy": "bolt"
        case "illuminance": "sun.max"
        case "carbon_dioxide", "pm25", "aqi": "aqi.medium"
        default: sensor.unit?.hasPrefix("°") == true ? "thermometer.medium" : "gauge.with.dots.needle.33percent"
        }
    }

    /// The room's first temperature sensor, for "Room 28°C" summaries.
    @MainActor
    static func temperatureSensor(_ room: Room?, store: EntityStore) -> HAState? {
        room?.headerSensors.lazy.compactMap { store[$0] }
            .first { $0.deviceClass == "temperature" || $0.unit?.hasPrefix("°") == true }
    }

    @MainActor
    static func roomTemperature(_ room: Room?, store: EntityStore) -> Double? {
        temperatureSensor(room, store: store)?.numericState
    }

}

// MARK: - Climate row

private struct ClimateRow: View {
    @Environment(AppModel.self) private var app
    let card: Card
    let room: Room

    var body: some View {
        let climate = app.store[card.entityID]
        let mode = climate?.state ?? "off"
        let isOn = mode != "off" && climate?.isAvailable == true
        let name = app.displayName(card)
        // Two tap areas, like the tiles: the chip toggles power, the rest opens the climate screen.
        ZStack(alignment: .leading) {
            Button {
                app.push(.card(card.id))
            } label: {
                HStack(spacing: 11) {
                    Color.clear.frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(summary(climate))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if isOn, let target = targetText(climate) {
                        Text(target)
                            .font(.system(size: target.count > 4 ? 18 : 26, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(TileBackground())
                .contentShape(.rect(cornerRadius: Theme.tileRadius))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(name), \(summary(climate))")
            .accessibilityHint("Opens \(name) controls")

            ClimatePowerChip(mode: mode, isOn: isOn, name: name) {
                app.setClimatePower(card.entityID, on: !isOn)
            }
            .padding(.leading, 12)
            .rollbackShake(card.entityID)
            .disabled(climate?.isAvailable != true)
        }
        .opacity(climate?.isAvailable == false ? 0.5 : 1)
        .animation(Theme.spring, value: isOn)
    }

    /// "24°", or "20–24°" for units holding a heat/cool range.
    private func targetText(_ climate: HAState?) -> String? {
        if let t = climate?.temperature { return "\(Int(t.rounded()))°" }
        if let low = climate?.targetTempLow, let high = climate?.targetTempHigh {
            return "\(Int(low.rounded()))–\(Int(high.rounded()))°"
        }
        return nil
    }

    private func summary(_ climate: HAState?) -> String {
        guard let climate else { return "Unavailable" }
        var parts = [HVACMode.name(climate.state)]
        if climate.state != "off" {
            let fan = card.attachment(.fanSpeed).flatMap { app.store[$0.entityID]?.state } ?? climate.fanMode
            if let fan, fan != "unknown" { parts.append("Fan \(ACOption.label(fan))") }
        }
        if let roomTemp = climate.currentTemperature ?? HeaderReadout.roomTemperature(room, store: app.store) {
            parts.append("Room \(Int(roomTemp.rounded()))\(app.temperatureUnit)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Mode-coloured icon chip on the climate row; tapping it turns the unit on or off.
private struct ClimatePowerChip: View {
    let mode: String
    let isOn: Bool
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let color = HVACMode.hex(mode).map { Color(hex: $0) } ?? Color.gray
        Button(action: action) {
            Image(systemName: isOn ? HVACMode.symbol(mode) : "power")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? color : Color.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(isOn ? color.opacity(0.22) : Color.primary.opacity(0.12)))
                .shadow(color: isOn ? color.opacity(0.5) : .clear, radius: 6)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
                        .padding(-3)
                        .opacity(hovering ? 1 : 0)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(isOn ? "Turn \(name) off" : "Turn \(name) on")
    }
}

extension View {
    /// Lets arrow keys land on this tile, with a focus ring while it has keyboard focus.
    func keyFocus(_ id: UUID, _ focus: FocusState<HomeFocus?>.Binding, radius: CGFloat = Theme.tileRadius) -> some View {
        modifier(KeyFocusRing(id: id, focus: focus, radius: radius))
    }
}

private struct KeyFocusRing: ViewModifier {
    let id: UUID
    var focus: FocusState<HomeFocus?>.Binding
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .focusable(interactions: .activate)
            .focused(focus, equals: .card(id))
            .focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .padding(-3)
                    .opacity(focus.wrappedValue == .card(id) ? 1 : 0)
                    .allowsHitTesting(false)
            }
    }
}
