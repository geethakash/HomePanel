import AppKit
import HAKit
import SwiftUI
import os

/// Screens inside the panel.
enum Route: Hashable {
    /// A card's device screen (switch, light, climate…).
    case card(UUID)
    case lightEffect(UUID)
    case climateOption(UUID, ACOption)
}

enum NavDirection { case forward, back }

/// App-wide state: the HA connection, the live entity store and panel navigation.
@MainActor
@Observable
final class AppModel {
    let store = EntityStore()
    /// The saved layout (rooms, sections and cards). Empty until set up.
    let config = ConfigStore()
    @ObservationIgnored let client = HAClient()

    private(set) var path: [Route] = []
    private(set) var navDirection: NavDirection = .forward
    private(set) var panelVisible = false
    private(set) var settingsVisible = false
    /// Shows the setup wizard even though HomePanel is set up ("Run Setup Again").
    var forceSetup = false
    /// Set before opening Settings to land on a tab ("rooms" from the panel's room list).
    var settingsTab: String?
    /// The home screen shows the room list instead of the room's sections.
    var showingRooms = false
    /// Edit mode in the panel: tiles wiggle, can be dragged to reorder and hidden.
    var editing = false
    var lastError: String?
    /// Areas, devices and entities in HA, loaded once per launch after the first connect.
    private(set) var catalog: EntityCatalog?

    @ObservationIgnored private var disconnectTask: Task<Void, Never>?
    @ObservationIgnored private var resetPathTask: Task<Void, Never>?
    @ObservationIgnored private var errorTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HomePanel", category: "App")

    /// How long to stay connected after the panel closes, so reopening is instant.
    private let lingerAfterClose: Duration = .seconds(60)
    /// How long the panel remembers the last screen while closed.
    private let rememberScreenFor: Duration = .seconds(30)

    init() {
        let events = client.events
        Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }
        let tokenLocation = TokenStore.migrateToSharedIfNeeded()
        log.notice("Token location: \(tokenLocation.rawValue, privacy: .public)")
        log.notice("Home Assistant URL saved: \(SharedConfig.hasSavedURL ? "yes" : "no", privacy: .public)")
        if tokenLocation == .none { store.status = .needsSetup }
        observeSubscription()
    }

    // MARK: Layout

    var currentRoom: Room? { config.config.room(config.config.lastRoomID) }

    /// The card with this ID and the section it's in.
    func locate(_ cardID: UUID) -> (section: CardSection, card: Card)? {
        config.config.locate(card: cardID).map { ($0.section, $0.card) }
    }

    /// Switches the panel to another room (which resubscribes to that room's entities) and
    /// remembers it for next time.
    func selectRoom(_ id: UUID) {
        guard config.config.rooms.contains(where: { $0.id == id }) else { return }
        withAnimation(Theme.spring) {
            showingRooms = false
            editing = false
        }
        guard id != currentRoom?.id else { return }
        if !path.isEmpty {
            navigate(.back) { $0.removeAll() }
        }
        withAnimation(.smooth(duration: 0.25)) {
            config.update { $0.lastRoomID = id }
        }
        log.notice("Room: \(self.currentRoom?.name ?? "?", privacy: .public)")
    }

    /// Adds generated rooms for these HA Areas (nil = devices with no area), and shows the first
    /// one if the panel had no rooms yet.
    func addRooms(forAreas areaIDs: [String?]) {
        guard let catalog, !areaIDs.isEmpty else { return }
        let rooms = areaIDs.map { LayoutGenerator.room(for: $0, in: catalog) }
        config.update { config in
            let hadRooms = !config.rooms.isEmpty
            config.rooms += rooms
            if !hadRooms { config.lastRoomID = rooms.first?.id }
        }
        log.notice("Added \(rooms.count) rooms from areas")
    }

    /// Whether the first-run setup should show: no token yet, or no rooms.
    var needsSetup: Bool {
        !TokenStore.hasToken || config.config.rooms.isEmpty
    }

    // MARK: Editing in the panel

    func setEditing(_ on: Bool) {
        withAnimation(Theme.spring) {
            editing = on
            if on { showingRooms = false }
        }
        if on, !path.isEmpty { navigate(.back) { $0.removeAll() } }
    }

    /// Moves a card in the current room to just before `target` (same section or another one).
    func moveCard(_ cardID: UUID, before target: UUID) {
        guard cardID != target, let roomID = currentRoom?.id else { return }
        withAnimation(Theme.spring) {
            config.update { config in
                guard let r = config.rooms.firstIndex(where: { $0.id == roomID }) else { return }
                var sections = config.rooms[r].sections
                guard let from = sections.firstIndex(where: { $0.cards.contains { $0.id == cardID } }),
                    let to = sections.firstIndex(where: { $0.cards.contains { $0.id == target } }),
                    let card = sections[from].cards.first(where: { $0.id == cardID })
                else { return }
                sections[from].cards.removeAll { $0.id == cardID }
                let index = sections[to].cards.firstIndex { $0.id == target } ?? sections[to].cards.endIndex
                sections[to].cards.insert(card, at: index)
                config.rooms[r].sections = sections
            }
        }
    }

    /// Moves a card to the end of a section in the current room.
    func moveCard(_ cardID: UUID, toEndOf sectionID: UUID) {
        guard let roomID = currentRoom?.id else { return }
        withAnimation(Theme.spring) {
            config.update { config in
                guard let r = config.rooms.firstIndex(where: { $0.id == roomID }),
                    let from = config.rooms[r].sections.firstIndex(where: { $0.cards.contains { $0.id == cardID } }),
                    let to = config.rooms[r].sections.firstIndex(where: { $0.id == sectionID }),
                    let card = config.rooms[r].sections[from].cards.first(where: { $0.id == cardID })
                else { return }
                config.rooms[r].sections[from].cards.removeAll { $0.id == cardID }
                config.rooms[r].sections[to].cards.append(card)
            }
        }
    }

    /// Moves a card one place earlier (-1) or later (+1) in its section.
    func nudgeCard(_ cardID: UUID, by offset: Int) {
        guard let roomID = currentRoom?.id else { return }
        withAnimation(Theme.spring) {
            config.update { config in
                guard let r = config.rooms.firstIndex(where: { $0.id == roomID }),
                    let s = config.rooms[r].sections.firstIndex(where: { $0.cards.contains { $0.id == cardID } }),
                    let i = config.rooms[r].sections[s].cards.firstIndex(where: { $0.id == cardID })
                else { return }
                let j = i + offset
                guard config.rooms[r].sections[s].cards.indices.contains(j) else { return }
                config.rooms[r].sections[s].cards.swapAt(i, j)
            }
        }
    }

    func toggleHidden(_ cardID: UUID) {
        guard let roomID = currentRoom?.id else { return }
        withAnimation(Theme.spring) {
            config.update { config in
                guard let r = config.rooms.firstIndex(where: { $0.id == roomID }) else { return }
                for s in config.rooms[r].sections.indices {
                    if let c = config.rooms[r].sections[s].cards.firstIndex(where: { $0.id == cardID }) {
                        config.rooms[r].sections[s].cards[c].hidden.toggle()
                    }
                }
            }
        }
    }

    /// Called after a whole new layout is imported.
    func layoutReplaced() {
        path = []
        showingRooms = false
    }

    /// Only the current room's cards, attachments and header sensors are subscribed.
    var subscribedEntityIDs: [String] {
        currentRoom.map(PanelConfig.entityIDs(in:)) ?? []
    }

    /// Resubscribes whenever the room or its cards change.
    private func observeSubscription() {
        let ids = withObservationTracking {
            subscribedEntityIDs
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSubscription() }
        }
        Task { await client.updateSubscription(entityIDs: ids) }
    }

    /// Loads the HA catalog (areas, devices, entities). `force` reloads it.
    func loadCatalog(force: Bool = false) async {
        guard force || catalog == nil else { return }
        do {
            catalog = try await HARegistry.fetchCatalog(client)
        } catch {
            log.error("Catalog failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The card's name, HA's friendly name, or the entity ID.
    func displayName(_ card: Card) -> String {
        card.name ?? store[card.entityID]?.friendlyName ?? card.entityID
    }

    // MARK: Navigation

    func push(_ route: Route) {
        guard !editing else { return }
        navigate(.forward) { $0.append(route) }
    }
    func pop() { navigate(.back) { _ = $0.popLast() } }

    private func navigate(_ direction: NavDirection, _ change: @escaping (inout [Route]) -> Void) {
        // Set the direction first and let it render, so the outgoing screen picks up the right transition.
        navDirection = direction
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.32)) { change(&self.path) }
        }
    }

    // MARK: Panel lifecycle

    func panelVisibilityChanged(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        if visible {
            disconnectTask?.cancel()
            resetPathTask?.cancel()
            connect()
        } else {
            if !settingsVisible { scheduleDisconnect() }
            resetPathTask = Task { [weak self, rememberScreenFor] in
                try? await Task.sleep(for: rememberScreenFor)
                guard !Task.isCancelled else { return }
                self?.path = []
                self?.showingRooms = false
                self?.editing = false
            }
        }
    }

    private func scheduleDisconnect() {
        disconnectTask?.cancel()
        disconnectTask = Task { [weak self, lingerAfterClose] in
            try? await Task.sleep(for: lingerAfterClose)
            guard !Task.isCancelled, let self, !self.panelVisible, !self.settingsVisible else { return }
            await self.client.stop()
        }
    }

    /// Settings also needs the connection (to list areas and devices), so it counts like the panel.
    func settingsVisibilityChanged(_ visible: Bool) {
        guard visible != settingsVisible else { return }
        settingsVisible = visible
        if visible {
            disconnectTask?.cancel()
            connect()
        } else if !panelVisible {
            scheduleDisconnect()
        }
    }

    func connect() {
        guard let url = SharedConfig.baseURL, let token = TokenStore.load() else {
            store.status = .needsSetup
            return
        }
        let ids = subscribedEntityIDs
        Task { await client.start(.init(baseURL: url, token: token), entityIDs: ids) }
    }

    /// Called after Settings saves a new URL or token.
    func settingsChanged() {
        store.removeAll()
        catalog = nil
        Task {
            await client.stop()
            connect()
            if !panelVisible { scheduleDisconnect() }
        }
    }

    private func handleWake() {
        guard panelVisible || disconnectTask != nil else { return }
        log.info("Woke from sleep, reconnecting")
        Task { await client.reconnect() }
    }

    private func handle(_ event: HAClient.Event) {
        switch event {
        case .status(let status):
            if status == .disconnected, store.status == .needsSetup { return }
            store.status = status
            if status == .connected, catalog == nil {
                Task { await loadCatalog() }
            }
        case .entities(let payload):
            store.apply(payload)
        }
    }

    // MARK: Actions

    func call(_ domain: String, _ service: String, _ entityIDs: [String], _ data: [String: JSONValue] = [:]) {
        Task {
            do {
                try await client.callService(domain, service, entityIDs: entityIDs, data: data)
            } catch {
                log.error("\(domain).\(service) failed: \(error.localizedDescription, privacy: .public)")
                showError(HAErrorText.describe(error))
                for id in entityIDs { store.clearOptimistic(id) }
            }
        }
    }

    private func showError(_ message: String) {
        lastError = message
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.lastError = nil
        }
    }

    private static func domain(of id: String) -> String { String(id.prefix { $0 != "." }) }

    func toggle(_ entityID: String) {
        guard let s = store[entityID] else { return }
        setOn([entityID], !s.isOn)
    }

    /// `turn_on` / `turn_off` for one or more entities of the same domain.
    func setOn(_ entityIDs: [String], _ on: Bool) {
        guard let first = entityIDs.first else { return }
        for id in entityIDs { store.setOptimistic(id, state: on ? "on" : "off") }
        call(Self.domain(of: first), on ? "turn_on" : "turn_off", entityIDs)
        if !on { cancelOffTimers(for: entityIDs) }
    }

    /// Manually turning a hub switch off cancels its "turn off after" timer.
    private func cancelOffTimers(for entityIDs: [String]) {
        let cards = config.config.rooms.flatMap(\.sections).flatMap(\.cards)
        let timers = cards
            .filter { entityIDs.contains($0.entityID) }
            .compactMap { $0.attachment(.offTimer)?.entityID }
            .filter { store.states[$0]?.state == "active" || store.states[$0]?.state == "paused" }
        if !timers.isEmpty { call("timer", "cancel", timers) }
    }

    /// Runs a scene, script or button; toggles anything else.
    func activate(_ entityID: String) {
        switch Self.domain(of: entityID) {
        case "scene": call("scene", "turn_on", [entityID])
        case "script": call("script", "turn_on", [entityID])
        case "button": call("button", "press", [entityID])
        case "input_button": call("input_button", "press", [entityID])
        default: toggle(entityID)
        }
    }

    func selectOption(_ entityID: String, _ option: String) {
        store.setOptimistic(entityID, state: option)
        call("select", "select_option", [entityID], ["option": .string(option)])
    }

    func setNumber(_ entityID: String, _ value: Double) {
        call("number", "set_value", [entityID], ["value": .number(value)])
    }

    func lightOn(_ entityID: String, _ data: [String: JSONValue]) {
        store.setOptimistic(entityID, state: "on")
        call("light", "turn_on", [entityID], data)
    }

    /// Turns the switch on and starts its HA timer; the HA automation turns it off when the timer ends.
    func startOffTimer(switchID: String, timerID: String, seconds: TimeInterval) {
        if store[switchID]?.isOn != true { setOn([switchID], true) }
        call("timer", "start", [timerID], ["duration": .string(HADate.formatDuration(seconds))])
    }

    func cancelOffTimer(timerID: String) {
        call("timer", "cancel", [timerID])
    }

    // MARK: Quick actions (a tile's icon)

    /// What tapping a tile's icon does. nil = it opens the device screen instead (e.g. unlocking
    /// a lock or arming an alarm, which want a confirmation or a code).
    enum QuickAction {
        case toggle, coverToggle, playPause, power, lock, run

        func label(_ name: String) -> String? {
            switch self {
            case .toggle, .power: nil
            case .coverToggle: "Open or close \(name)"
            case .playPause: "Play or pause \(name)"
            case .lock: "Lock \(name)"
            case .run: "Run \(name)"
            }
        }
    }

    func quickAction(_ card: Card) -> QuickAction? {
        let state = store[card.entityID]
        switch card.kind {
        case .toggle, .fan, .light: return .toggle
        case .cover:
            return state?.coverFeatures.isDisjoint(with: [.open, .close]) == false ? .coverToggle : nil
        case .media:
            guard let state else { return nil }
            let f = state.mediaFeatures
            if ["playing", "paused"].contains(state.state), !f.isDisjoint(with: [.pause, .play]) { return .playPause }
            return f.isDisjoint(with: [.turnOn, .turnOff]) ? nil : .power
        case .lock: return state?.state == "unlocked" ? .lock : nil
        case .scene, .script, .button: return .run
        case .climate, .alarm, .sensor, .binarySensor, .select, .number: return nil
        }
    }

    func perform(_ action: QuickAction, _ card: Card) {
        let id = card.entityID
        switch action {
        case .toggle: toggle(id)
        case .coverToggle: call("cover", "toggle", [id])
        case .playPause: call("media_player", "media_play_pause", [id])
        case .power: call("media_player", store[id]?.state == "off" ? "turn_on" : "turn_off", [id])
        case .lock: call("lock", "lock", [id])
        case .run: activate(id)
        }
    }

    /// Scenes, scripts and buttons just run; everything else has a device screen.
    func hasScreen(_ card: Card) -> Bool {
        ![.scene, .script, .button].contains(card.kind)
    }

    // MARK: Climate

    /// Turning on lets the unit resume its last mode, so only "off" is shown optimistically.
    /// Units without `climate.turn_on` get their first mode instead.
    func setClimatePower(_ entityID: String, on: Bool) {
        guard on else {
            store.setOptimistic(entityID, state: "off")
            call("climate", "turn_off", [entityID])
            return
        }
        let fallback = HVACMode.sorted(store[entityID]?.hvacModes ?? []).first
        Task {
            do {
                try await client.callService("climate", "turn_on", entityIDs: [entityID])
            } catch HAClientError.serviceError(let code, _) where fallback != nil {
                log.info("turn_on unsupported (\(code, privacy: .public)), setting mode instead")
                setHVACMode(entityID, fallback!)
            } catch {
                log.error("climate.turn_on failed: \(error.localizedDescription, privacy: .public)")
                showError(HAErrorText.describe(error))
            }
        }
    }

    func setHVACMode(_ entityID: String, _ mode: String) {
        store.setOptimistic(entityID, state: mode)
        call("climate", "set_hvac_mode", [entityID], ["hvac_mode": .string(mode)])
    }

    func setFanMode(_ entityID: String, _ mode: String) {
        call("climate", "set_fan_mode", [entityID], ["fan_mode": .string(mode)])
    }

    func setTemperature(_ entityID: String, _ temperature: Double) {
        call("climate", "set_temperature", [entityID], ["temperature": .number(temperature)])
    }

    /// For heat/cool units that hold a range instead of one target.
    func setTemperatureRange(_ entityID: String, low: Double, high: Double) {
        call(
            "climate", "set_temperature", [entityID],
            ["target_temp_low": .number(low), "target_temp_high": .number(high)])
    }

    /// `climate.set_swing_mode`, `set_preset_mode`… (`key` is the data field, e.g. "swing_mode").
    func setClimateOption(_ entityID: String, service: String, key: String, _ value: String) {
        call("climate", service, [entityID], [key: .string(value)])
    }

    /// Applies a climate setting, whether it's an attached select or the climate's own mode.
    func apply(_ setting: ClimateSetting, _ value: String, climateID: String) {
        switch setting.source {
        case .select(let id): selectOption(id, value)
        case .climate(let service, let key): setClimateOption(climateID, service: service, key: key, value)
        }
    }

    /// HA's temperature unit, or the room sensor's, or just "°".
    var temperatureUnit: String {
        catalog?.temperatureUnit ?? HeaderReadout.temperatureSensor(currentRoom, store: store)?.unit ?? "°"
    }
}
